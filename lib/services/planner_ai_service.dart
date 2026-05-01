// ============================================================
//  services/planner_service.dart  (REBUILT — replaces planner_ai_service.dart)
//
//  Production trip planner for GeoGuide.
//
//  Design:
//  - Quality-based candidate selection (not random)
//  - Geographic clustering for same-day proximity
//  - Gemini AI for intelligent ordering when key available
//  - Deterministic geographic fallback (never empty)
//  - Strict city filtering: only places from selected city
//  - Max 5 places/day, respects requested days exactly
// ============================================================

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:geoguide/core/place_category_normalizer.dart';
import 'package:geoguide/models.dart/landmark_model.dart';

enum PlannerEngine { gemini, local }

class PlannerResult {
  final List<List<Landmark>> days;
  final PlannerEngine engine;
  final String note;

  const PlannerResult({
    required this.days,
    required this.engine,
    required this.note,
  });
}

class PlannerService {
  PlannerService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const String _geminiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const String _geminiModel =
      String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-2.5-flash');

  bool get _hasGemini => _geminiKey.trim().isNotEmpty;

  // ════════════════════════════════════════════════════════
  //  PUBLIC API
  // ════════════════════════════════════════════════════════

  Future<PlannerResult> generatePlan({
    required List<Landmark> landmarks,
    required int days,
    String? cityName,
    int? variationSeed,
  }) async {
    if (landmarks.isEmpty || days <= 0) {
      return const PlannerResult(
        days: [],
        engine: PlannerEngine.local,
        note: 'No places available.',
      );
    }

    final safeDays = days.clamp(1, 7);
    final seed =
        variationSeed ?? DateTime.now().microsecondsSinceEpoch % 999999;

    // 1. Filter to allowed categories + deduplicate + same city
    final candidates = _prepareCandidates(landmarks, cityName, safeDays, seed);

    if (candidates.isEmpty) {
      return const PlannerResult(
        days: [],
        engine: PlannerEngine.local,
        note: 'No suitable places found.',
      );
    }

    // 2. Try Gemini first
    if (_hasGemini) {
      try {
        final geminiPlan = await _callGemini(
          landmarks: candidates,
          days: safeDays,
          cityName: cityName,
          seed: seed,
        );

        if (_isValidPlan(geminiPlan, candidates, safeDays)) {
          final polished =
              _postProcess(geminiPlan, candidates, safeDays, seed: seed);
          return PlannerResult(
            days: polished,
            engine: PlannerEngine.gemini,
            note: 'AI plan for ${cityName ?? 'Egypt'}.',
          );
        }
      } catch (e) {
        print('[Planner] Gemini failed ($e) — using local fallback');
      }
    }

    // 3. Local geographic fallback
    final fallback = _geographicFallback(candidates, safeDays, seed: seed);
    return PlannerResult(
      days: fallback,
      engine: PlannerEngine.local,
      note: _hasGemini
          ? 'AI unavailable — using smart local plan.'
          : 'Local smart plan.',
    );
  }

  // ════════════════════════════════════════════════════════
  //  CANDIDATE PREPARATION
  // ════════════════════════════════════════════════════════

  List<Landmark> _prepareCandidates(
    List<Landmark> raw,
    String? cityName,
    int days,
    int seed,
  ) {
    // 1. Filter to allowed categories
    final allowed = raw.where((lm) {
      return PlaceCategoryNormalizer.isAllowed(lm.category,
          contextText: lm.name);
    }).toList();

    // 2. Same-city filter
    final sameCity = (cityName ?? '').trim().isEmpty
        ? allowed
        : allowed.where((lm) {
            final lmCity = lm.city.trim().toLowerCase();
            final hint = cityName!.trim().toLowerCase();
            return lmCity == hint ||
                lmCity.contains(hint) ||
                hint.contains(lmCity);
          }).toList();

    if (sameCity.isEmpty) return [];

    // 3. Deduplicate
    final deduped = _deduplicate(sameCity);

    // 4. Score and select top N
    final maxNeeded = _maxPlacesForDays(days);
    deduped.sort((a, b) => _qualityScore(b).compareTo(_qualityScore(a)));

    return deduped.take(maxNeeded).toList();
  }

  List<Landmark> _deduplicate(List<Landmark> items) {
    final seen = <String>{};
    final result = <Landmark>[];
    for (final lm in items) {
      final key =
          '${lm.name.trim().toLowerCase()}|${lm.city.trim().toLowerCase()}';
      if (seen.add(key)) result.add(lm);
    }
    return result;
  }

  // ════════════════════════════════════════════════════════
  //  GEMINI AI
  // ════════════════════════════════════════════════════════

  Future<List<List<Landmark>>> _callGemini({
    required List<Landmark> landmarks,
    required int days,
    String? cityName,
    required int seed,
  }) async {
    final prompt = _buildPrompt(
        landmarks: landmarks, days: days, cityName: cityName, seed: seed);

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$_geminiModel:generateContent?key=$_geminiKey',
    );

    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0.55,
              'topP': 0.9,
              'topK': 40,
              'maxOutputTokens': 1200,
              'responseMimeType': 'application/json',
            }
          }),
        )
        .timeout(const Duration(seconds: 28));

    if (response.statusCode != 200) {
      throw Exception('Gemini HTTP ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final text = _extractGeminiText(body);
    if (text.trim().isEmpty) throw Exception('Gemini empty response');

    return _parseGeminiResponse(text, landmarks);
  }

  String _extractGeminiText(Map<String, dynamic> body) {
    final candidates = body['candidates'] as List? ?? const [];
    if (candidates.isEmpty) return '';
    final content =
        (candidates.first as Map<String, dynamic>)['content'] as Map? ?? {};
    final parts = (content['parts'] as List? ?? const []);
    if (parts.isEmpty) return '';
    return (parts.first as Map<String, dynamic>)['text']?.toString() ?? '';
  }

  List<List<Landmark>> _parseGeminiResponse(
      String text, List<Landmark> source) {
    final byName = {
      for (final lm in source) lm.name.trim().toLowerCase(): lm,
    };

    dynamic decoded;
    try {
      decoded = jsonDecode(text.trim());
    } catch (_) {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start == -1 || end <= start) throw Exception('No JSON found');
      decoded = jsonDecode(text.substring(start, end + 1));
    }

    if (decoded is! Map<String, dynamic>) throw Exception('Not an object');

    final rawDays = decoded['days'] as List? ?? const [];
    final result = <List<Landmark>>[];

    for (final rawDay in rawDays) {
      final rawPlaces = (rawDay is Map<String, dynamic>)
          ? (rawDay['places'] as List? ?? const [])
          : (rawDay as List? ?? const []);

      final day = <Landmark>[];
      final usedInDay = <String>{};

      for (final rawName in rawPlaces) {
        final key = rawName.toString().trim().toLowerCase();
        if (key.isEmpty) continue;
        final found = byName[key];
        if (found != null && usedInDay.add(key)) {
          day.add(found);
        }
      }

      result.add(day);
    }

    return result;
  }

  String _buildPrompt({
    required List<Landmark> landmarks,
    required int days,
    String? cityName,
    required int seed,
  }) {
    final placeList = landmarks
        .map((e) => {
              'name': e.name,
              'category': e.category,
              'rating': e.rating,
              'lat': e.lat,
              'lng': e.lng,
            })
        .toList();

    return '''
You are a smart Egypt travel planner. Create a realistic day-by-day trip plan.

City: ${cityName ?? 'Egypt'}
Days: $days
Variation: $seed

Rules:
- Use ONLY the provided places.
- Max 5 places per day.
- Minimize travel distance within each day (group nearby places together).
- Balance category types across days when possible.
- No duplicates across days.
- Valid JSON only.

Format:
{"days":[{"places":["Name1","Name2"]},{"places":["Name3"]}]}

Available places:
${jsonEncode(placeList)}
''';
  }

  // ════════════════════════════════════════════════════════
  //  VALIDATION
  // ════════════════════════════════════════════════════════

  bool _isValidPlan(
    List<List<Landmark>> plan,
    List<Landmark> source,
    int days,
  ) {
    if (plan.isEmpty || plan.length != days) return false;

    final sourceNames =
        source.map((e) => e.name.trim().toLowerCase()).toSet();
    final used = <String>{};
    bool hasAny = false;

    for (final day in plan) {
      if (day.length > 5) return false;
      for (final place in day) {
        final key = place.name.trim().toLowerCase();
        if (!sourceNames.contains(key)) return false;
        if (!used.add(key)) return false;
        hasAny = true;
      }
    }

    return hasAny;
  }

  // ════════════════════════════════════════════════════════
  //  POST-PROCESSING (ensures min fills, category balance)
  // ════════════════════════════════════════════════════════

  List<List<Landmark>> _postProcess(
    List<List<Landmark>> rawPlan,
    List<Landmark> source,
    int days, {
    required int seed,
  }) {
    final idealLoad = _idealDayLoad(days);
    final used = <String>{};

    final result = List.generate(days, (_) => <Landmark>[]);

    // Copy from raw plan (respect used set)
    for (int i = 0; i < math.min(rawPlan.length, days); i++) {
      for (final place in rawPlan[i]) {
        final key = place.name.trim().toLowerCase();
        if (used.add(key)) result[i].add(place);
      }
      // Enforce max 5 per day
      while (result[i].length > 5) {
        result[i].removeLast();
      }
    }

    // Remaining candidates
    final leftovers = source
        .where((lm) => !used.contains(lm.name.trim().toLowerCase()))
        .toList()
      ..sort((a, b) => _qualityScore(b).compareTo(_qualityScore(a)));

    // Fill days that are under ideal load
    for (int d = 0; d < result.length; d++) {
      while (result[d].length < idealLoad && leftovers.isNotEmpty) {
        final best = _pickBest(leftovers, result[d]);
        if (best == null) break;
        used.add(best.name.trim().toLowerCase());
        result[d].add(best);
        leftovers.removeWhere(
          (e) => e.name.trim().toLowerCase() == best.name.trim().toLowerCase(),
        );
      }
    }

    // Sort each day by quality descending
    for (final day in result) {
      day.sort((a, b) => _qualityScore(b).compareTo(_qualityScore(a)));
    }

    return result;
  }

  Landmark? _pickBest(List<Landmark> pool, List<Landmark> daySoFar) {
    if (pool.isEmpty) return null;

    Landmark? best;
    double bestScore = -1;

    for (final candidate in pool) {
      double score = _qualityScore(candidate);

      // Proximity bonus
      if (daySoFar.isNotEmpty) {
        final last = daySoFar.last;
        final dist = _distanceKm(last.lat, last.lng, candidate.lat, candidate.lng);
        if (dist > 0 && dist <= 5) score += 8;
        else if (dist <= 15) score += 3;
      }

      // Category diversity bonus
      final dayCats = daySoFar
          .map((e) => PlaceCategoryNormalizer.normalize(e.category))
          .toSet();
      final candCat = PlaceCategoryNormalizer.normalize(candidate.category);
      if (!dayCats.contains(candCat)) score += 3;

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    return best;
  }

  // ════════════════════════════════════════════════════════
  //  GEOGRAPHIC FALLBACK
  // ════════════════════════════════════════════════════════

  List<List<Landmark>> _geographicFallback(
    List<Landmark> candidates,
    int days, {
    required int seed,
  }) {
    if (candidates.isEmpty) {
      return List.generate(days, (_) => <Landmark>[]);
    }

    // Sort by quality
    final sorted = [...candidates]
      ..sort((a, b) => _qualityScore(b).compareTo(_qualityScore(a)));

    final result = List.generate(days, (_) => <Landmark>[]);
    final used = <String>{};
    final idealLoad = _idealDayLoad(days);

    for (int dayIndex = 0; dayIndex < days; dayIndex++) {
      // Pick anchor (highest quality unused)
      Landmark? anchor;
      for (final lm in sorted) {
        final key = lm.name.trim().toLowerCase();
        if (used.add(key)) {
          anchor = lm;
          result[dayIndex].add(lm);
          break;
        }
      }

      if (anchor == null) break;

      // Fill day based on proximity to anchor
      final pool = sorted
          .where((lm) => !used.contains(lm.name.trim().toLowerCase()))
          .toList()
        ..sort((a, b) {
          final da = _distanceKm(anchor!.lat, anchor.lng, a.lat, a.lng);
          final db = _distanceKm(anchor.lat, anchor.lng, b.lat, b.lng);
          return da.compareTo(db);
        });

      for (final candidate in pool) {
        if (result[dayIndex].length >= idealLoad) break;
        final key = candidate.name.trim().toLowerCase();
        if (used.add(key)) {
          result[dayIndex].add(candidate);
        }
      }
    }

    return _postProcess(result, candidates, days, seed: seed);
  }

  // ════════════════════════════════════════════════════════
  //  SCORING
  // ════════════════════════════════════════════════════════

  double _qualityScore(Landmark lm) {
    double score = 0;

    score += lm.rating * 3;

    final cat = PlaceCategoryNormalizer.normalize(lm.category,
        contextText: lm.name);
    if (cat == 'tourist') score += 8;
    if (cat == 'outing') score += 4;
    if (cat == 'restaurant') score += 2;
    if (cat == 'cafe') score += 1;
    if (cat == 'hotel') score += 1;

    if (lm.wikipediaUrl?.isNotEmpty == true) score += 3;
    if (lm.imageUrl.trim().isNotEmpty || lm.mediaUrls.isNotEmpty) score += 2;
    if (lm.shortDescription.trim().length > 60) score += 2;
    if (lm.lat != 0 && lm.lng != 0) score += 2;

    // Famous landmark bonus
    final name = lm.name.toLowerCase();
    for (final iconic in _iconicKeywords) {
      if (name.contains(iconic)) {
        score += 6;
        break;
      }
    }

    return score;
  }

  // ════════════════════════════════════════════════════════
  //  GEOMETRY
  // ════════════════════════════════════════════════════════

  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    if (lat1 == 0 || lng1 == 0 || lat2 == 0 || lng2 == 0) return 999;
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _rad(double deg) => deg * math.pi / 180;

  // ════════════════════════════════════════════════════════
  //  CONSTANTS
  // ════════════════════════════════════════════════════════

  int _maxPlacesForDays(int days) {
    if (days <= 1) return 5;
    if (days == 2) return 9;
    if (days == 3) return 12;
    if (days <= 5) return 14;
    return 18;
  }

  int _idealDayLoad(int days) {
    if (days <= 1) return 5;
    if (days == 2) return 4;
    if (days <= 4) return 3;
    return 2;
  }

  static const List<String> _iconicKeywords = [
    'pyramid',
    'sphinx',
    'karnak',
    'luxor temple',
    'valley of the kings',
    'abu simbel',
    'philae',
    'qaitbay',
    'citadel',
    'khan el-khalili',
    'bibliotheca',
    'hatshepsut',
    'colossi',
    'kom ombo',
    'edfu',
    'siwa',
    'egyptian museum',
  ];
}