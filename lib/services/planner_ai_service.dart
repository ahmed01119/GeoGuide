// ============================================================
//  services/planner_ai_service.dart
//
//  GeoGuide Professional Trip Planner
//
//  Features:
//  - Gemini-first planning
//  - Time-aware prompt using opening hours
//  - Smart local fallback when Gemini fails
//  - New plan on every Generate click, even same city
//  - Hybrid strategy: famous core places + fresh varied places
//  - Logical day routing: morning landmarks, lunch restaurants,
//    afternoon outings, evening markets/cafes/views
//  - Opening-hours-aware ordering when data is available
//  - Strict city filtering
//  - Max 5 places/day
// ============================================================

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:geoguide/core/config/app_config.dart';
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
  PlannerService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String get _geminiKey => AppConfig.geminiApiKey;
  String get _geminiModel => AppConfig.geminiModel;
  bool get _hasGemini => AppConfig.hasValidGeminiKey;

  int _generationCounter = 0;
  final Map<String, String> _lastPlanSignatureByScope = {};

  // ════════════════════════════════════════════════════════
  //  PUBLIC API
  // ════════════════════════════════════════════════════════

  Future<PlannerResult> generatePlan({
    required List<Landmark> landmarks,
    required int days,
    String? cityName,
    int? variationSeed,
  }) async {
    final safeDays = days.clamp(1, 7).toInt();

    if (landmarks.isEmpty || safeDays <= 0) {
      return const PlannerResult(
        days: [],
        engine: PlannerEngine.local,
        note: 'No places available.',
      );
    }

    final baseSeed = variationSeed ?? _freshSeed();
    final scopeKey = _scopeKey(cityName, safeDays);

    PlannerResult? firstValidResult;

    // 1) Gemini first: high-quality intelligent plan.
    if (_hasGemini) {
      for (int attempt = 0; attempt < 2; attempt++) {
        final attemptSeed = baseSeed + (attempt * 10007);
        final candidates = _prepareCandidates(
          landmarks,
          cityName,
          safeDays,
          attemptSeed,
        );

        if (candidates.isEmpty) continue;

        try {
          final geminiPlan = await _callGemini(
            landmarks: candidates,
            days: safeDays,
            cityName: cityName,
            seed: attemptSeed,
          );

          if (_isValidPlan(geminiPlan, candidates, safeDays)) {
            final polished = _postProcess(
              geminiPlan,
              candidates,
              safeDays,
              seed: attemptSeed,
            );

            final result = PlannerResult(
              days: polished,
              engine: PlannerEngine.gemini,
              note: 'Professional AI plan for ${cityName ?? 'Egypt'}.',
            );

            firstValidResult ??= result;

            if (_isNewEnough(scopeKey, polished, candidates)) {
              _rememberSignature(scopeKey, polished);
              return result;
            }
          }
        } catch (e) {
          print('[Planner] Gemini attempt $attempt failed: $e');
        }
      }
    }

    // 2) Local fallback: never leave the user without a plan.
    for (int attempt = 0; attempt < 4; attempt++) {
      final attemptSeed = baseSeed + 50000 + (attempt * 7919);
      final candidates = _prepareCandidates(
        landmarks,
        cityName,
        safeDays,
        attemptSeed,
      );

      if (candidates.isEmpty) continue;

      final fallbackPlan = _geographicFallback(
        candidates,
        safeDays,
        seed: attemptSeed,
      );

      if (_isValidPlan(fallbackPlan, candidates, safeDays)) {
        final result = PlannerResult(
          days: fallbackPlan,
          engine: PlannerEngine.local,
          note: _hasGemini
              ? 'AI unavailable or repeated — using a fresh professional local plan.'
              : 'Fresh professional local plan.',
        );

        firstValidResult ??= result;

        if (_isNewEnough(scopeKey, fallbackPlan, candidates)) {
          _rememberSignature(scopeKey, fallbackPlan);
          return result;
        }
      }
    }

    if (firstValidResult != null) {
      _rememberSignature(scopeKey, firstValidResult.days);
      return firstValidResult;
    }

    return const PlannerResult(
      days: [],
      engine: PlannerEngine.local,
      note: 'No suitable places found.',
    );
  }

  int _freshSeed() {
    _generationCounter++;
    final now = DateTime.now().microsecondsSinceEpoch;
    return (now + (_generationCounter * 1000003)) & 0x7fffffff;
  }

  String _scopeKey(String? cityName, int days) {
    final city = (cityName ?? 'egypt').trim().toLowerCase();
    return '$city|$days';
  }

  String _planSignature(List<List<Landmark>> plan) {
    return plan
        .map(
          (day) => day
              .map((e) => e.name.trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .join('>'),
        )
        .join('|');
  }

  bool _isNewEnough(
    String scopeKey,
    List<List<Landmark>> plan,
    List<Landmark> candidates,
  ) {
    final signature = _planSignature(plan);
    final last = _lastPlanSignatureByScope[scopeKey];

    if (last == null || last != signature) return true;

    final usedCount = plan.expand((e) => e).length;
    final uniqueCandidates = candidates
        .map((e) => e.name.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .length;

    // If there are not enough alternatives, repetition may be unavoidable.
    return uniqueCandidates <= usedCount;
  }

  void _rememberSignature(String scopeKey, List<List<Landmark>> plan) {
    _lastPlanSignatureByScope[scopeKey] = _planSignature(plan);
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
    final allowed = raw.where((lm) {
      return PlaceCategoryNormalizer.isAllowed(
        lm.category,
        contextText: '${lm.name} ${lm.shortDescription} ${lm.description}',
      );
    }).toList();

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

    final deduped = _deduplicate(sameCity);
    if (deduped.isEmpty) return [];

    return _buildVariedCandidatePool(deduped, days, seed);
  }

  List<Landmark> _deduplicate(List<Landmark> items) {
    final seen = <String>{};
    final result = <Landmark>[];

    for (final lm in items) {
      final name = lm.name.trim().toLowerCase();
      final city = lm.city.trim().toLowerCase();

      if (name.isEmpty) continue;

      final key = '$name|$city';
      if (seen.add(key)) result.add(lm);
    }

    return result;
  }

  List<Landmark> _buildVariedCandidatePool(
    List<Landmark> items,
    int days,
    int seed,
  ) {
    final maxNeeded = _maxPlacesForDays(days);
    final poolSize = math.min(
      items.length,
      math.max(maxNeeded * 2, 24),
    );

    final scored = [...items];

    scored.sort((a, b) {
      final aScore = _qualityScore(a) + _stableJitter(a.name, seed, 10);
      final bScore = _qualityScore(b) + _stableJitter(b.name, seed, 10);
      return bScore.compareTo(aScore);
    });

    // Hybrid strategy:
    // Keep a famous core, then vary secondary places using seed.
    final coreLimit = days <= 1 ? 2 : math.min(5, days + 2);
    final iconic = scored.where(_isIconic).take(coreLimit).toList();

    final rest = scored.where((e) {
      return !iconic.any(
        (x) => x.name.trim().toLowerCase() == e.name.trim().toLowerCase(),
      );
    }).toList();

    rest.sort((a, b) {
      final aScore = _qualityScore(a) + _stableJitter(a.name, seed + 17, 18);
      final bScore = _qualityScore(b) + _stableJitter(b.name, seed + 17, 18);
      return bScore.compareTo(aScore);
    });

    final result = <Landmark>[];
    final used = <String>{};

    for (final lm in [...iconic, ...rest]) {
      final key = lm.name.trim().toLowerCase();
      if (used.add(key)) result.add(lm);
      if (result.length >= poolSize) break;
    }

    return result;
  }

  double _stableJitter(String key, int seed, double maxValue) {
    final randomSeed = (seed ^ key.toLowerCase().hashCode) & 0x7fffffff;
    return math.Random(randomSeed).nextDouble() * maxValue;
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
      landmarks: landmarks,
      days: days,
      cityName: cityName,
      seed: seed,
    );

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$_geminiModel:generateContent?key=$_geminiKey',
    );

    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.78,
        'topP': 0.9,
        'topK': 40,
        'maxOutputTokens': 4096,
        'responseMimeType': 'application/json',
        'responseSchema': {
          'type': 'object',
          'properties': {
            'days': {
              'type': 'array',
              'items': {
                'type': 'array',
                'items': {'type': 'string'},
              },
            },
          },
          'required': ['days'],
        },
      },
    };

    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Gemini HTTP ${response.statusCode}: ${response.body}');
    }

    final decodedBody = jsonDecode(response.body) as Map<String, dynamic>;
    final text = _extractGeminiText(decodedBody);

    if (text.trim().isEmpty) {
      throw Exception('Gemini empty response');
    }

    return _parseGeminiResponse(text, landmarks);
  }

  String _extractGeminiText(Map<String, dynamic> body) {
    final candidates = body['candidates'] as List? ?? const [];

    if (candidates.isEmpty) {
      final promptFeedback = body['promptFeedback'];
      print('[Planner] Gemini no candidates. promptFeedback=$promptFeedback');
      return '';
    }

    final buffer = StringBuffer();

    for (final candidate in candidates) {
      if (candidate is! Map<String, dynamic>) continue;

      final finishReason = candidate['finishReason'];
      if (finishReason != null) {
        print('[Planner] Gemini finishReason=$finishReason');
      }

      final content = candidate['content'] as Map? ?? {};
      final parts = content['parts'] as List? ?? const [];

      for (final part in parts) {
        if (part is Map && part['text'] != null) {
          buffer.writeln(part['text'].toString());
        }
      }
    }

    return buffer.toString().trim();
  }

  List<List<Landmark>> _parseGeminiResponse(
    String text,
    List<Landmark> source,
  ) {
    final byName = {
      for (final lm in source) lm.name.trim().toLowerCase(): lm,
    };

    final cleanText = text.trim();
    if (cleanText.isEmpty) throw Exception('Gemini empty text');

    dynamic decoded;

    try {
      decoded = jsonDecode(cleanText);
    } catch (_) {
      try {
        final fenced = RegExp(
          r'```(?:json)?\s*([\s\S]*?)\s*```',
          caseSensitive: false,
        ).firstMatch(cleanText);

        if (fenced != null) {
          decoded = jsonDecode(fenced.group(1)!.trim());
        } else {
          final objectStart = cleanText.indexOf('{');
          final objectEnd = cleanText.lastIndexOf('}');
          final arrayStart = cleanText.indexOf('[');
          final arrayEnd = cleanText.lastIndexOf(']');

          if (objectStart != -1 && objectEnd > objectStart) {
            decoded = jsonDecode(cleanText.substring(objectStart, objectEnd + 1));
          } else if (arrayStart != -1 && arrayEnd > arrayStart) {
            decoded = jsonDecode(cleanText.substring(arrayStart, arrayEnd + 1));
          } else {
            final recovered = _recoverPlanFromPlainText(cleanText, source);
            if (recovered.isNotEmpty) return recovered;

            print('[Planner] Gemini raw non-json response:\n$cleanText');
            throw Exception('No JSON found in Gemini response');
          }
        }
      } catch (e) {
        print('[Planner] Gemini raw response parse failed:\n$cleanText');
        throw Exception('Could not parse Gemini JSON: $e');
      }
    }

    final result = <List<Landmark>>[];

    if (decoded is Map<String, dynamic>) {
      final rawDays = decoded['days'] as List? ?? const [];

      for (final rawDay in rawDays) {
        final rawPlaces = rawDay is Map<String, dynamic>
            ? rawDay['places'] as List? ?? const []
            : rawDay as List? ?? const [];

        final day = _placesFromRawNames(rawPlaces, byName);
        result.add(day);
      }

      return result;
    }

    if (decoded is List) {
      for (final rawDay in decoded) {
        final rawPlaces = rawDay is Map<String, dynamic>
            ? rawDay['places'] as List? ?? const []
            : rawDay as List? ?? const [];

        final day = _placesFromRawNames(rawPlaces, byName);
        result.add(day);
      }

      return result;
    }

    throw Exception('Unsupported Gemini JSON format');
  }

  List<Landmark> _placesFromRawNames(
    List rawPlaces,
    Map<String, Landmark> byName,
  ) {
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

    return day;
  }

  List<List<Landmark>> _recoverPlanFromPlainText(
    String text,
    List<Landmark> source,
  ) {
    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (lines.isEmpty) return const [];

    final result = <List<Landmark>>[];
    List<Landmark> currentDay = [];
    final used = <String>{};

    bool hasDayMarkers = false;

    for (final line in lines) {
      final lower = line.toLowerCase();

      if (RegExp(r'\bday\s*\d+\b').hasMatch(lower) ||
          RegExp(r'\bاليوم\s*\d+\b').hasMatch(lower)) {
        hasDayMarkers = true;
        if (currentDay.isNotEmpty) {
          result.add(currentDay);
          currentDay = [];
        }
        continue;
      }

      for (final place in source) {
        final name = place.name.trim();
        final key = name.toLowerCase();

        if (used.contains(key)) continue;

        if (lower.contains(key)) {
          used.add(key);
          currentDay.add(place);
        }
      }
    }

    if (currentDay.isNotEmpty) result.add(currentDay);
    if (!hasDayMarkers && result.length == 1) return result;

    return result;
  }

  String _buildPrompt({
    required List<Landmark> landmarks,
    required int days,
    String? cityName,
    required int seed,
  }) {
    final places = landmarks
        .take(35)
        .map(
          (e) => {
            'name': e.name.trim(),
            'category': PlaceCategoryNormalizer.normalize(
              e.category,
              contextText: '${e.name} ${e.shortDescription} ${e.description}',
            ),
            'rating': e.rating,
            'openingHours': e.openingHours.trim().isEmpty
                ? 'unknown'
                : e.openingHours.trim(),
            'bestTime': _bestTimeLabel(e),
            'lat': _roundCoord(e.lat),
            'lng': _roundCoord(e.lng),
          },
        )
        .where((e) => (e['name'] ?? '').toString().isNotEmpty)
        .toList();

    return '''
Return ONLY valid JSON. No markdown. No explanation.

You are GeoGuide's professional Egypt trip planner.

City: ${cityName ?? 'Egypt'}
Days: $days
Variation seed: $seed

Goal:
Create a fresh, realistic, high-quality trip plan.

Planning rules:
- Use ONLY names from the provided list.
- Names must match exactly.
- No duplicate places.
- Max 5 places per day.
- Hybrid quality: include famous core attractions, then vary secondary places.
- Make each Generate click feel different using the variation seed.
- Group nearby places together.
- Respect openingHours when known.
- Do not put a place at a time when it is likely closed.
- Museums, monuments, citadels, temples, and historical sites are best in morning or early afternoon.
- Restaurants are best around lunch or dinner.
- Cafes, markets, towers, parks, and outing places can be afternoon/evening.
- Avoid a random plan. Each day must have a logical flow.

Return this exact JSON shape:
{
  "days": [
    ["Place 1", "Place 2"],
    ["Place 3"]
  ]
}

Available places:
${jsonEncode(places)}
''';
  }

  double _roundCoord(double value) => (value * 10000).round() / 10000;

  // ════════════════════════════════════════════════════════
  //  VALIDATION
  // ════════════════════════════════════════════════════════

  bool _isValidPlan(
    List<List<Landmark>> plan,
    List<Landmark> source,
    int days,
  ) {
    if (plan.isEmpty || plan.length != days) return false;

    final sourceNames = source.map((e) => e.name.trim().toLowerCase()).toSet();
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
  //  POST PROCESSING
  // ════════════════════════════════════════════════════════

  List<List<Landmark>> _postProcess(
    List<List<Landmark>> rawPlan,
    List<Landmark> source,
    int days, {
    required int seed,
  }) {
    final idealLoad = _idealDayLoad(days);
    final result = List.generate(days, (_) => <Landmark>[]);
    final used = <String>{};

    for (int i = 0; i < math.min(rawPlan.length, days); i++) {
      for (final place in rawPlan[i]) {
        final key = place.name.trim().toLowerCase();
        if (key.isEmpty) continue;
        if (result[i].length >= 5) break;

        if (used.add(key)) {
          result[i].add(place);
        }
      }
    }

    final leftovers = source.where((lm) {
      return !used.contains(lm.name.trim().toLowerCase());
    }).toList();

    leftovers.sort((a, b) {
      final aScore = _qualityScore(a) + _stableJitter(a.name, seed + 31, 8);
      final bScore = _qualityScore(b) + _stableJitter(b.name, seed + 31, 8);
      return bScore.compareTo(aScore);
    });

    for (int d = 0; d < result.length; d++) {
      while (result[d].length < idealLoad && leftovers.isNotEmpty) {
        final best = _pickBest(
          leftovers,
          result[d],
          seed: seed + d,
        );

        if (best == null) break;

        final key = best.name.trim().toLowerCase();
        if (used.add(key)) result[d].add(best);

        leftovers.removeWhere(
          (e) => e.name.trim().toLowerCase() == key,
        );
      }
    }

    for (int d = 0; d < result.length; d++) {
      result[d] = _routeOrder(
        result[d],
        seed: seed + (d * 101),
      );
    }

    return result;
  }

  Landmark? _pickBest(
    List<Landmark> pool,
    List<Landmark> daySoFar, {
    required int seed,
  }) {
    if (pool.isEmpty) return null;

    Landmark? best;
    double bestScore = -999999;

    for (final candidate in pool) {
      double score = _qualityScore(candidate);
      score += _stableJitter(candidate.name, seed, 7);

      if (daySoFar.isNotEmpty) {
        final avgDist = _averageDistanceToDay(candidate, daySoFar);

        if (avgDist <= 3) {
          score += 12;
        } else if (avgDist <= 8) {
          score += 8;
        } else if (avgDist <= 15) {
          score += 4;
        } else if (avgDist > 40 && avgDist < 999) {
          score -= 8;
        }
      }

      final dayCats = daySoFar
          .map((e) => PlaceCategoryNormalizer.normalize(
                e.category,
                contextText: e.name,
              ))
          .toSet();

      final candidateCat = PlaceCategoryNormalizer.normalize(
        candidate.category,
        contextText: candidate.name,
      );

      if (!dayCats.contains(candidateCat)) score += 3;

      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    return best;
  }

  // ════════════════════════════════════════════════════════
  //  LOCAL FALLBACK
  // ════════════════════════════════════════════════════════

  List<List<Landmark>> _geographicFallback(
    List<Landmark> candidates,
    int days, {
    required int seed,
  }) {
    if (candidates.isEmpty) return List.generate(days, (_) => <Landmark>[]);

    final sorted = [...candidates];

    sorted.sort((a, b) {
      final aScore = _qualityScore(a) + _stableJitter(a.name, seed + 77, 14);
      final bScore = _qualityScore(b) + _stableJitter(b.name, seed + 77, 14);
      return bScore.compareTo(aScore);
    });

    final result = List.generate(days, (_) => <Landmark>[]);
    final used = <String>{};
    final idealLoad = _idealDayLoad(days);

    for (int dayIndex = 0; dayIndex < days; dayIndex++) {
      final unused = sorted.where((lm) {
        return !used.contains(lm.name.trim().toLowerCase());
      }).toList();

      if (unused.isEmpty) break;

      final anchor = _chooseAnchor(
        unused,
        seed: seed + (dayIndex * 911),
      );

      final anchorKey = anchor.name.trim().toLowerCase();
      used.add(anchorKey);
      result[dayIndex].add(anchor);

      while (result[dayIndex].length < idealLoad) {
        final pool = sorted.where((lm) {
          return !used.contains(lm.name.trim().toLowerCase());
        }).toList();

        if (pool.isEmpty) break;

        final next = _pickBest(
          pool,
          result[dayIndex],
          seed: seed + (dayIndex * 113) + result[dayIndex].length,
        );

        if (next == null) break;

        final key = next.name.trim().toLowerCase();
        used.add(key);
        result[dayIndex].add(next);
      }
    }

    return _postProcess(result, candidates, days, seed: seed);
  }

  Landmark _chooseAnchor(
    List<Landmark> unused, {
    required int seed,
  }) {
    final pool = [...unused];

    pool.sort((a, b) {
      final aScore = _qualityScore(a) + _stableJitter(a.name, seed, 12);
      final bScore = _qualityScore(b) + _stableJitter(b.name, seed, 12);
      return bScore.compareTo(aScore);
    });

    final topLimit = math.min(pool.length, 5);
    final index = math.Random(seed & 0x7fffffff).nextInt(topLimit);

    return pool[index];
  }

  List<Landmark> _routeOrder(
    List<Landmark> day, {
    required int seed,
  }) {
    if (day.length <= 1) return day;

    final remaining = [...day];
    final ordered = <Landmark>[];
    final slotHours = _slotHoursForDay(day.length);

    Landmark? previous;

    for (int i = 0; i < slotHours.length && remaining.isNotEmpty; i++) {
      final hour = slotHours[i];

      remaining.sort((a, b) {
        final aScore = _slotFitScore(a, hour, previous, seed + i);
        final bScore = _slotFitScore(b, hour, previous, seed + i);
        return bScore.compareTo(aScore);
      });

      final selected = remaining.removeAt(0);
      ordered.add(selected);
      previous = selected;
    }

    return ordered;
  }

  List<double> _slotHoursForDay(int count) {
    if (count <= 1) return const [10.0];
    if (count == 2) return const [10.0, 17.0];
    if (count == 3) return const [9.5, 13.5, 17.5];
    if (count == 4) return const [9.5, 12.5, 16.0, 19.0];
    return const [9.0, 11.5, 14.0, 17.0, 20.0];
  }

  double _slotFitScore(
    Landmark lm,
    double hour,
    Landmark? previous,
    int seed,
  ) {
    double score = _qualityScore(lm);
    score += _timePreferenceScore(lm, hour);
    score += _isProbablyOpenAt(lm, hour) ? 10 : -18;
    score += _stableJitter(lm.name, seed, 4);

    if (previous != null) {
      final dist = _distanceKm(previous.lat, previous.lng, lm.lat, lm.lng);
      if (dist <= 3) score += 8;
      else if (dist <= 8) score += 5;
      else if (dist <= 15) score += 2;
      else if (dist > 35 && dist < 999) score -= 7;
    }

    return score;
  }

  double _timePreferenceScore(Landmark lm, double hour) {
    final label = _bestTimeLabel(lm);

    if (label == 'morning') {
      if (hour >= 8 && hour <= 12.5) return 14;
      if (hour <= 15) return 6;
      return -5;
    }

    if (label == 'lunch') {
      if (hour >= 12 && hour <= 15) return 14;
      if (hour >= 18 && hour <= 21) return 8;
      return -2;
    }

    if (label == 'afternoon') {
      if (hour >= 15 && hour <= 18.5) return 12;
      if (hour >= 10 && hour < 15) return 4;
      return -2;
    }

    if (label == 'evening') {
      if (hour >= 17 && hour <= 22) return 14;
      if (hour >= 14 && hour < 17) return 5;
      return -6;
    }

    return 0;
  }

  String _bestTimeLabel(Landmark lm) {
    final cat = PlaceCategoryNormalizer.normalize(
      lm.category,
      contextText: '${lm.name} ${lm.shortDescription} ${lm.description}',
    );

    final text = '${lm.name} ${lm.category} ${lm.shortDescription} ${lm.description}'
        .toLowerCase();

    if (cat == 'restaurant') return 'lunch';
    if (cat == 'cafe') return 'evening';

    if (text.contains('market') ||
        text.contains('bazaar') ||
        text.contains('khan') ||
        text.contains('tower') ||
        text.contains('corniche')) {
      return 'evening';
    }

    if (cat == 'outing' ||
        text.contains('park') ||
        text.contains('garden') ||
        text.contains('mall') ||
        text.contains('beach')) {
      return 'afternoon';
    }

    if (cat == 'tourist' ||
        text.contains('museum') ||
        text.contains('temple') ||
        text.contains('pyramid') ||
        text.contains('citadel') ||
        text.contains('palace') ||
        text.contains('historic')) {
      return 'morning';
    }

    return 'flexible';
  }

  bool _isProbablyOpenAt(Landmark lm, double hour) {
    final hours = lm.openingHours.trim().toLowerCase();
    if (hours.isEmpty || hours == 'unknown') return true;

    if (hours.contains('24') || hours.contains('all day')) return true;
    if (hours.contains('closed')) return false;

    final intervals = _parseOpeningIntervals(hours);
    if (intervals.isEmpty) return true;

    for (final interval in intervals) {
      final start = interval.$1;
      final end = interval.$2;

      if (start <= end) {
        if (hour >= start && hour <= end) return true;
      } else {
        // Overnight interval, e.g. 6 PM - 2 AM.
        if (hour >= start || hour <= end) return true;
      }
    }

    return false;
  }

  List<(double, double)> _parseOpeningIntervals(String raw) {
    final text = raw
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('to', '-')
        .replaceAll(RegExp(r'\s+'), ' ');

    final regex = RegExp(
      r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*-\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?',
      caseSensitive: false,
    );

    final intervals = <(double, double)>[];

    for (final match in regex.allMatches(text)) {
      final startHour = int.tryParse(match.group(1) ?? '');
      final startMin = int.tryParse(match.group(2) ?? '0') ?? 0;
      final startAmPm = match.group(3);

      final endHour = int.tryParse(match.group(4) ?? '');
      final endMin = int.tryParse(match.group(5) ?? '0') ?? 0;
      final endAmPm = match.group(6);

      if (startHour == null || endHour == null) continue;

      final start = _to24Hour(startHour, startMin, startAmPm, fallbackPm: false);
      final end = _to24Hour(endHour, endMin, endAmPm, fallbackPm: true);

      intervals.add((start, end));
    }

    return intervals;
  }

  double _to24Hour(
    int hour,
    int minute,
    String? ampm, {
    required bool fallbackPm,
  }) {
    var h = hour;
    final marker = ampm?.toLowerCase();

    if (marker == 'pm' && h < 12) h += 12;
    if (marker == 'am' && h == 12) h = 0;

    // If no AM/PM exists, keep 24h-looking values as-is.
    // For common tourist strings like 9 - 5, assume 9 AM - 5 PM.
    if (marker == null && fallbackPm && h <= 8) h += 12;

    return h + (minute / 60.0);
  }

  // ════════════════════════════════════════════════════════
  //  SCORING
  // ════════════════════════════════════════════════════════

  double _qualityScore(Landmark lm) {
    double score = 0;

    score += lm.rating * 3;

    final cat = PlaceCategoryNormalizer.normalize(
      lm.category,
      contextText: '${lm.name} ${lm.shortDescription} ${lm.description}',
    );

    if (cat == 'tourist') score += 10;
    if (cat == 'outing') score += 5;
    if (cat == 'restaurant') score += 3;
    if (cat == 'cafe') score += 2;
    if (cat == 'hotel') score += 1;

    if (lm.wikipediaUrl?.isNotEmpty == true) score += 4;
    if (lm.imageUrl.trim().isNotEmpty || lm.mediaUrls.isNotEmpty) score += 3;
    if (lm.shortDescription.trim().length > 60) score += 2;
    if (lm.lat != 0 && lm.lng != 0) score += 3;
    if (lm.openingHours.trim().isNotEmpty) score += 1.5;
    if (_isIconic(lm)) score += 8;

    return score;
  }

  bool _isIconic(Landmark lm) {
    final name = lm.name.toLowerCase();

    for (final iconic in _iconicKeywords) {
      if (name.contains(iconic)) return true;
    }

    return false;
  }

  // ════════════════════════════════════════════════════════
  //  GEOMETRY
  // ════════════════════════════════════════════════════════

  double _averageDistanceToDay(Landmark candidate, List<Landmark> day) {
    if (day.isEmpty) return 999;

    double total = 0;
    int valid = 0;

    for (final place in day) {
      final d = _distanceKm(
        candidate.lat,
        candidate.lng,
        place.lat,
        place.lng,
      );

      if (d < 999) {
        total += d;
        valid++;
      }
    }

    if (valid == 0) return 999;
    return total / valid;
  }

  double _distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
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
    if (days <= 5) return 15;
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
    'pyramids',
    'sphinx',
    'karnak',
    'luxor temple',
    'valley of the kings',
    'abu simbel',
    'philae',
    'qaitbay',
    'citadel',
    'khan el-khalili',
    'khan el khalili',
    'bibliotheca',
    'alexandrina',
    'hatshepsut',
    'colossi',
    'kom ombo',
    'edfu',
    'siwa',
    'egyptian museum',
    'grand egyptian museum',
    'cairo tower',
    'al azhar',
    'mohamed ali',
    'muhammad ali',
    'saladin',
    'montaza',
    'catacombs',
    'abdeen palace',
  ];
}
