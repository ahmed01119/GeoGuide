// ============================================================
//  services/search-service.dart
//  GENERIC SEARCH ENGINE - STRICT PLACE VALIDATION
//
//  Fixes in this version:
//  - Search is generic: Firebase first, then OSM/Nominatim, then Wikipedia.
//  - Selected city is used ONLY for generic category queries like cafes/hotels.
//  - A generated place is saved under its REAL city from OSM/Wikipedia, not the
//    currently selected dropdown city.
//  - Blocks non-place results such as attacks, incidents, wars, events, etc.
//  - Does not save weak OSM/Wikipedia results that are not real Egyptian places.
//  - Returns the exact searched place first when it is found/generated.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:geoguide/core/config/app_config.dart';
import 'package:geoguide/core/place_category_normalizer.dart';
import 'package:geoguide/core/place_search_pipeline.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/services/semantic-score.dart';
import 'package:geoguide/services/Wikipedia%20service.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/services/image-service.dart';
import 'package:geoguide/services/landmark_cache.dart';
import 'package:geoguide/services/nearby-service.dart';

class SearchResult {
  final String correctedQuery;
  final List<Landmark> results;
  final List<String> suggestions;
  final String? detectedCity;
  final String? detectedCategory;
  /// Egyptian city inferred from explicit wording in the query (e.g. Hurghada).
  final String? cityIntent;
  /// True when the query is a generic category browse ("cafes in Cairo"), not a named place.
  final bool isGenericCategoryQuery;
  /// Parallel to [results]: provenance for debugging (null when omitted).
  final List<PlaceResultSource>? resultSources;

  const SearchResult({
    required this.correctedQuery,
    required this.results,
    this.suggestions = const [],
    this.detectedCity,
    this.detectedCategory,
    this.cityIntent,
    this.isGenericCategoryQuery = false,
    this.resultSources,
  });

  static const empty = SearchResult(
    correctedQuery: '',
    results: [],
    resultSources: null,
    cityIntent: null,
    isGenericCategoryQuery: false,
  );
}

class _CategoryListingMatch {
  final String category;
  final String citySegment;

  const _CategoryListingMatch({
    required this.category,
    required this.citySegment,
  });
}

class SearchEngine {
  SearchEngine({
    FirebaseService? firebase,
    WikipediaService? wikipedia,
    NearbyService? nearby,
    ImageService? images,
  })  : _firebase = firebase ?? FirebaseService(),
        _wikipedia = wikipedia ?? WikipediaService(),
        _nearby = nearby ?? NearbyService(),
        _images = images ?? ImageService(),
        _cache = LandmarkCache.instance;

  final FirebaseService _firebase;
  final WikipediaService _wikipedia;
  final NearbyService _nearby;
  final ImageService _images;
  final LandmarkCache _cache;

  List<Landmark>? _index;
  DateTime? _indexTimestamp;
  static const Duration _indexTtl = Duration(minutes: 10);

  String _lastHintKey = '';
  List<String> _lastHints = [];

  // Prevent repeated background saves for the same category/city batch.
  final Set<String> _backgroundSaveKeys = {};

  /// Short cooldown after Nominatim/network failures to avoid hammering providers.
  final Map<String, DateTime> _providerCooldownUntil = {};

  bool _isProviderCoolingDown(String key) {
    final until = _providerCooldownUntil[key];
    return until != null && DateTime.now().isBefore(until);
  }

  void _cooldownProvider(String key, {Duration duration = const Duration(minutes: 2)}) {
    _providerCooldownUntil[key] = DateTime.now().add(duration);
    if (kDebugMode) {
      debugPrint('[SearchEngine] provider cooldown until ${_providerCooldownUntil[key]} key=$key');
    }
  }

  _CategoryListingMatch? _tryParseCategoryListingQuery(String raw) {
    final n = _normalizeSearchText(raw);
    if (n.isEmpty) return null;

    final m = RegExp(r'^(.+?)\s+(?:in|near|around|at|في)\s+(.+)$').firstMatch(n);
    if (m == null) return null;
    final left = _stripListingCategoryFiller(m.group(1)!.trim());
    final right = m.group(2)!.trim();
    if (left.isEmpty || right.isEmpty) return null;

    final cat = _categoryPhraseToListingCategory(left);
    if (cat == null) return null;
    return _CategoryListingMatch(category: cat, citySegment: right);
  }

  String _stripListingCategoryFiller(String phrase) {
    var p = phrase.trim();
    for (final w in [
      'best', 'top', 'famous', 'popular', 'nice', 'good', 'great', 'amazing',
      'recommended', 'beautiful',
    ]) {
      p = p.replaceFirst(RegExp('^$w\\s+'), '');
    }
    return p.trim();
  }

  String? _categoryPhraseToListingCategory(String phraseNorm) {
    final p = phraseNorm.trim();
    if (p.isEmpty) return null;

    final entries = <(String, String)>[
      ('tourist attractions', 'tourist'),
      ('tourist attraction', 'tourist'),
      ('historic sites', 'tourist'),
      ('historic site', 'tourist'),
      ('outing places', 'outing'),
      ('outing place', 'outing'),
      ('shopping malls', 'outing'),
      ('shopping mall', 'outing'),
      ('coffee shops', 'cafe'),
      ('coffee shop', 'cafe'),
      ('public parks', 'outing'),
      ('public park', 'outing'),
      ('amusement parks', 'outing'),
      ('theme parks', 'outing'),
      ('theme park', 'outing'),
      ('night life', 'outing'),
      ('parks', 'outing'),
      ('park', 'outing'),
      ('gardens', 'outing'),
      ('garden', 'outing'),
      ('malls', 'outing'),
      ('mall', 'outing'),
      ('beaches', 'outing'),
      ('beach', 'outing'),
      ('marinas', 'outing'),
      ('marina', 'outing'),
      ('promenades', 'outing'),
      ('promenade', 'outing'),
      ('corniches', 'outing'),
      ('corniche', 'outing'),
      ('souks', 'outing'),
      ('souk', 'outing'),
      ('markets', 'outing'),
      ('market', 'outing'),
      ('bazaars', 'outing'),
      ('bazaar', 'outing'),
      ('entertainment', 'outing'),
      ('nightlife', 'outing'),
      ('restaurants', 'restaurant'),
      ('restaurant', 'restaurant'),
      ('cafes', 'cafe'),
      ('cafe', 'cafe'),
      ('hotels', 'hotel'),
      ('hotel', 'hotel'),
      ('hostels', 'hotel'),
      ('hostel', 'hotel'),
      ('museums', 'tourist'),
      ('museum', 'tourist'),
      ('landmarks', 'tourist'),
      ('landmark', 'tourist'),
      ('attractions', 'tourist'),
      ('attraction', 'tourist'),
      ('sightseeing', 'tourist'),
    ];
    entries.sort((a, b) => b.$1.length.compareTo(a.$1.length));

    for (final e in entries) {
      if (p == e.$1) return e.$2;
    }
    for (final e in entries) {
      if (p.contains(e.$1)) return e.$2;
    }
    return null;
  }

  bool _isKnownSpecificPlacePhrase(String raw) {
    final n = _normalizeSearchText(raw);
    if (n.isEmpty) return false;
    for (final name in _famousPlaces) {
      if (_normalizeSearchText(name) == n) return true;
    }
    for (final e in _aliases.entries) {
      if (_normalizeSearchText(e.key) == n) return true;
      for (final a in e.value) {
        if (_normalizeSearchText(a) == n) return true;
      }
    }
    return false;
  }

  bool _outingResultAcceptableForCategorySearch(Landmark lm) {
    if (PlaceSearchPipeline.isVerifiedVisitorOutingLandmark(lm)) return true;
    final c = PlaceCategoryNormalizer.normalize(lm.category, contextText: lm.name);
    if (c != 'outing') return false;
    final osmClass = (lm.sources?['osm_class'] ?? lm.sources?['class'] ?? '').toString();
    final osmType = (lm.sources?['osm_type'] ?? lm.sources?['type'] ?? '').toString();
    return PlaceSearchPipeline.isVerifiedVisitorOutingCandidate(
      name: lm.name,
      displayName: '${lm.shortDescription} ${lm.address}',
      osmClass: osmClass,
      osmType: osmType,
    );
  }

  Future<Landmark?> _geminiSuggestNamedPlace({
    required String rawQuery,
    String? cityHint,
    String? categoryHint,
  }) async {
    final primaryKey = AppConfig.geminiApiKey.trim();
    final fallbackKey = AppConfig.geminiFallbackApiKey.trim();
    final model = AppConfig.geminiModel.trim();

    if (primaryKey.isEmpty || model.isEmpty) return null;

    Uri geminiUri(String apiKey) => Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:generateContent?key=$apiKey',
    );

    final cleanCityHint = cityHint?.trim() ?? '';
    final cityHintIsGlobal = cleanCityHint.isEmpty;

    final prompt = '''
You are a strict Egyptian tourism place resolver.

Your task:
Resolve exactly ONE specific real place in Egypt from the user's search query.

User query:
"${rawQuery.trim()}"

City hint:
"${cityHintIsGlobal ? 'NO_CITY_HINT' : cleanCityHint}"

Category hint:
"${categoryHint ?? 'unknown'}"

Allowed scope:
You ONLY resolve real places in Egypt that belong to ONE of these five categories:
- tourist
- outing
- hotel
- restaurant
- cafe

Category meanings:
- tourist: landmarks, museums, historical sites, temples, monuments, palaces, citadels, mosques, churches, monasteries, tourist attractions
- outing: visitor-friendly places such as beaches, parks, gardens, malls, marinas, promenades, corniches, entertainment places, markets, bazaars, lakes, oases, islands, bays, reefs, diving or snorkeling places
- hotel: hotels, resorts, hostels
- restaurant: restaurants and food places
- cafe: cafes and coffee shops

Out-of-scope inputs:
Reject anything outside the five allowed categories.
Examples:
- hospitals
- clinics
- schools
- universities
- offices
- companies
- residential compounds
- streets as standalone places
- random services
- political places or events
- medical places
- programming, technical, personal, school, or general knowledge topics
- incidents, wars, attacks, news, or events
- fictional, vague, or unknown places

If the user query is outside the allowed categories:
Do NOT create a place.
Do NOT invent a related tourist place.
Return this empty rejected JSON object:
{
  "name": "",
  "displayName": "",
  "city": "",
  "lat": 0,
  "lng": 0,
  "category": "tourist",
  "address": "",
  "aliases": [],
  "shortDescription": "",
  "confidence": 0.0,
  "reason": "out_of_scope"
}

Matching rules:
1. Return exactly ONE real Egyptian place only.
2. The place must strongly match the user's query by official name, common name, alias, Arabic name, transliteration, or spelling variation.
3. Do NOT return unrelated famous places.
4. Do NOT return generic city attractions unless the query clearly refers to them.
5. Do NOT invent places, coordinates, addresses, categories, aliases, or names.
6. If the query is ambiguous, fictional, too vague, not tourism-related, or you cannot identify a real place confidently, return the empty rejected JSON object.
7. If a city hint is provided, use it only if it does not contradict the real location of the place.
8. If no city hint is provided, infer the most likely Egyptian city/governorate from the exact place name.
9. If you cannot confidently infer the city, return the empty rejected JSON object.
10. Coordinates must be inside Egypt and reasonably accurate.
11. If coordinates are unknown, return the empty rejected JSON object.
12. Confidence must reflect certainty:
   - 0.80 to 1.00: exact known place
   - 0.55 to 0.79: likely match
   - 0.35 to 0.54: weak match, needs review
   - below 0.35: uncertain, unknown, or rejected
13. Return JSON only.
14. Do not include markdown.
15. Do not include explanations outside JSON.
16. Do not wrap the JSON in code fences.
17. Do not return arrays.
18. Do not return multiple places.

Required JSON schema:
{
  "name": "",
  "displayName": "",
  "city": "",
  "lat": 0,
  "lng": 0,
  "category": "tourist|outing|hotel|restaurant|cafe",
  "address": "",
  "aliases": [],
  "shortDescription": "",
  "confidence": 0.0,
  "reason": ""
}

Field rules:
- name: official or most common English name.
- displayName: user-friendly display name. If unknown, use the same value as name.
- city: Egyptian city/governorate where the place actually belongs.
- lat: real latitude inside Egypt only.
- lng: real longitude inside Egypt only.
- category: exactly one of tourist, outing, hotel, restaurant, cafe.
- address: short address or area if known.
- aliases: alternative names, Arabic names, transliterations, or spelling variations.
- shortDescription: one short sentence about the place.
- confidence: numeric value from 0.0 to 1.0.
- reason: short reason why this place matches or why it was rejected.

Return only valid compact JSON.
''';

    try {
      final uriNamed = geminiUri(primaryKey);

      final res = await http
          .post(
            uriNamed,
            headers: {'Content-Type': 'application/json'},

            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {
                'temperature': 0.2,
                'maxOutputTokens': 512,
                'responseMimeType': 'application/json',
              },
            }),
          )
          .timeout(const Duration(seconds: 28));

      if (res.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[SearchEngine] Gemini named place HTTP ${res.statusCode}');
        }
        return null;
      }

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final text = _extractGeminiJsonText(decoded);
      if (text.trim().isEmpty) return null;

      final map = jsonDecode(text) as Map<String, dynamic>;
      final name = (map['name'] ?? '').toString().trim();
      final city = (map['city'] ?? '').toString().trim();
      final displayName = (map['displayName'] ?? '').toString().trim();
final shortDescription = (map['shortDescription'] ?? '').toString().trim();
final reason = (map['reason'] ?? '').toString().trim();

final aliases = <String>[];
final rawAliases = map['aliases'];
if (rawAliases is List) {
  for (final a in rawAliases) {
    final clean = a.toString().trim();
    if (clean.isNotEmpty) aliases.add(clean);
  }
}
      final lat = (map['lat'] is num) ? (map['lat'] as num).toDouble() : double.tryParse('${map['lat']}') ?? 0;
      final lng = (map['lng'] is num) ? (map['lng'] as num).toDouble() : double.tryParse('${map['lng']}') ?? 0;
      final catRaw = (map['category'] ?? 'tourist').toString();
      final address = (map['address'] ?? '').toString().trim();
      final conf = (map['confidence'] is num) ? (map['confidence'] as num).toDouble() : double.tryParse('${map['confidence']}') ?? 0;

      if (name.isEmpty || city.isEmpty || city.toLowerCase() == 'egypt' || conf < 0.42) {
        return null;
      }
      if (lat == 0 || lng == 0) return null;

      final cat = PlaceCategoryNormalizer.normalize(catRaw, contextText: name);
      if (!PlaceCategoryNormalizer.allowed.contains(cat)) return null;

      final lm = Landmark(
  id: '',
  name: name,
  displayName: displayName.isNotEmpty ? displayName : name,
  normalizedName: PlaceSearchPipeline.normalizeSearchQuery(name),
  aliases: aliases,
  cityId: '',
  city: city,
  category: cat,
  description: shortDescription.isNotEmpty
      ? shortDescription
      : address.isNotEmpty
          ? address
          : name,
  shortDescription: shortDescription.isNotEmpty
      ? shortDescription
      : address.isNotEmpty
          ? address
          : name,
  fullDescription: '',
  history: '',
  imageUrl: '',
  mediaUrls: const [],
  lat: lat,
  lng: lng,
  address: address.isNotEmpty ? address : city,
  rating: 0,
  openingHours: '',
  location: '$lat, $lng',
  ticketPrice: null,
  wikipediaUrl: null,
  createdAt: DateTime.now(),
  generatedBySearch: true,
  sources: {
    'provider': 'gemini_place_suggest',
    'confidence': conf.toString(),
    if (reason.isNotEmpty) 'reason': reason,
    'promptVersion': 'named_place_strict_v2',
  },
);

      if (!_looksEgyptianPlace('${lm.name} ${lm.city}', lm.city)) return null;
      if (_isBlockedNonPlaceResult(name: lm.name, displayName: lm.description, category: lm.category)) {
        return null;
      }
      if (!_filterNamedPlacesStrict(
        candidates: [lm],
        rawQuery: rawQuery,
        cityIntent: cityHint,
        maxKeep: 1,
      ).isNotEmpty) {
        return null;
      }
      return lm;
    } catch (e) {
      if (kDebugMode) debugPrint('[SearchEngine] Gemini named place error: $e');
      return null;
    }
  }

  String _extractGeminiJsonText(Map<String, dynamic> body) {
    final candidates = body['candidates'] as List? ?? const [];
    if (candidates.isEmpty) return '';
    final buf = StringBuffer();
    for (final c in candidates) {
      if (c is! Map) continue;
      final content = c['content'] as Map? ?? {};
      for (final part in (content['parts'] as List? ?? const [])) {
        if (part is Map && part['text'] != null) buf.write(part['text']);
      }
    }
    return buf.toString().trim();
  }

  Future<List<Landmark>> _geminiSuggestCategoryPlaces({
    required String category,
    required String cityName,
    required String rawQuery,
    required int maxResults,
  }) async {
    if (!AppConfig.hasValidGeminiKey) return [];
    final key = AppConfig.geminiApiKey.trim();
    final model = AppConfig.geminiModel.trim();
    if (key.isEmpty || model.isEmpty) return [];

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:generateContent?key=$key',
    );

    final outingNote = category == 'outing'
        ? 'Only visitor-friendly outings: beaches, parks, gardens, malls, marinas, promenades, markets, entertainment. No hospitals, schools, offices, streets, or residential compounds.'
        : '';

    final prompt =
        'List real or well-known $category places in $cityName, Egypt. $outingNote\n'
        'User query context: "${rawQuery.trim()}".\n'
        'Return JSON: {"places":[{"name":"","lat":0,"lng":0,"address":"","confidence":0.8}]}\n'
        'Max ${math.min(maxResults, 10)} items. Omit uncertain rows (confidence < 0.5). '
        'Coordinates must be in Egypt near $cityName.';

    try {
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {
                'temperature': 0.35,
                'maxOutputTokens': 2048,
                'responseMimeType': 'application/json',
              },
            }),
          )
          .timeout(const Duration(seconds: 35));

      if (res.statusCode != 200) return [];

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final text = _extractGeminiJsonText(decoded);
      if (text.isEmpty) return [];

      final map = jsonDecode(text) as Map<String, dynamic>;
      final list = (map['places'] as List?) ?? const [];
      final out = <Landmark>[];
      for (final item in list) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final name = (m['name'] ?? '').toString().trim();
        final lat = (m['lat'] is num) ? (m['lat'] as num).toDouble() : double.tryParse('${m['lat']}') ?? 0;
        final lng = (m['lng'] is num) ? (m['lng'] as num).toDouble() : double.tryParse('${m['lng']}') ?? 0;
        final address = (m['address'] ?? '').toString().trim();
        final conf = (m['confidence'] is num) ? (m['confidence'] as num).toDouble() : 0.75;
        if (name.isEmpty || lat == 0 || lng == 0 || conf < 0.45) continue;

        final lm = Landmark(
          id: '',
          name: name,
          cityId: '',
          city: cityName.trim(),
          category: category,
          description: address.isNotEmpty ? address : name,
          shortDescription: address.isNotEmpty ? address : name,
          fullDescription: '',
          history: '',
          imageUrl: '',
          mediaUrls: const [],
          lat: lat,
          lng: lng,
          address: address.isNotEmpty ? address : cityName,
          rating: 0,
          openingHours: '',
          location: '$lat, $lng',
          ticketPrice: null,
          wikipediaUrl: null,
          createdAt: DateTime.now(),
          generatedBySearch: true,
          sources: {
            'provider': 'gemini_category_suggest',
            'confidence': conf.toString(),
          },
        );

        if (!PlaceCategoryNormalizer.isAllowed(lm.category, contextText: lm.name)) continue;
        if (_isBlockedNonPlaceResult(name: lm.name, displayName: lm.description, category: category)) {
          continue;
        }
        if (category == 'outing' && !PlaceSearchPipeline.isVerifiedVisitorOutingCandidate(
              name: lm.name,
              displayName: lm.description,
              osmClass: '',
              osmType: '',
            )) {
          continue;
        }
        out.add(lm);
        if (out.length >= maxResults) break;
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('[SearchEngine] Gemini category error: $e');
      return [];
    }
  }

  static const Set<String> _providerGeneratedCategories = {
    'hotel',
    'restaurant',
    'cafe',
    'tourist',
    'outing',
  };

  static const Map<String, String> _canonicalCityMap = {
    'great pyramid of giza': 'Giza',
    'great pyramid': 'Giza',
    'pyramids of giza': 'Giza',
    'giza pyramids': 'Giza',
    'giza plateau': 'Giza',
    'pyramid of khufu': 'Giza',
    'khufu pyramid': 'Giza',
    'الأهرامات': 'Giza',
    'الاهرامات': 'Giza',
    'اهرامات الجيزة': 'Giza',
    'أهرامات الجيزة': 'Giza',
    'الهرم': 'Giza',
    'great sphinx of giza': 'Giza',
    'sphinx': 'Giza',
    'ابو الهول': 'Giza',
    'أبو الهول': 'Giza',
    'egyptian museum': 'Cairo',
    'grand egyptian museum': 'Giza',
    'khan el-khalili': 'Cairo',
    'citadel of cairo': 'Cairo',
    'cairo tower': 'Cairo',
    'abdeen palace': 'Cairo',
    'luxor temple': 'Luxor',
    'karnak temple': 'Luxor',
    'valley of the kings': 'Luxor',
    'hatshepsut temple': 'Luxor',
    'temple of hatshepsut': 'Luxor',
    'edfu temple': 'Aswan',
    'temple of edfu': 'Aswan',
    'kom ombo temple': 'Aswan',
    'temple of kom ombo': 'Aswan',
    'philae temple': 'Aswan',
    'abu simbel': 'Aswan',
    'bibliotheca alexandrina': 'Alexandria',
    'alexandria library': 'Alexandria',
    'citadel of qaitbay': 'Alexandria',
    'qaitbay citadel': 'Alexandria',
    'montaza palace': 'Alexandria',
    'montazah palace': 'Alexandria',
    'catacombs of kom el shoqafa': 'Alexandria',
    'siwa oasis': 'Siwa',
    'blue hole': 'Dahab',
    'ras mohammed': 'Sharm El Sheikh',
  };

  static const Map<String, List<String>> _aliases = {
    'great pyramid of giza': [
      'great pyramid',
      'giza pyramid',
      'giza pyramids',
      'pyramids of giza',
      'giza plateau',
      'khufu pyramid',
      'pyramid of khufu',
      'the pyramids',
      'pyramids',
      'الأهرامات',
      'الاهرامات',
      'اهرامات الجيزة',
      'أهرامات الجيزة',
      'الهرم',
    ],
    'great sphinx of giza': [
      'sphinx',
      'giza sphinx',
      'ابو الهول',
      'أبو الهول',
    ],
    'citadel of qaitbay': ['qaitbay', 'qaitbay citadel'],
    'karnak temple': ['karnak'],
    'luxor temple': ['luxor temple'],
    'philae temple': ['philae'],
    'abu simbel temples': ['abu simbel'],
    'bibliotheca alexandrina': ['alexandria library'],
    'temple of edfu': ['edfu temple', 'edfu'],
    'temple of kom ombo': ['kom ombo temple', 'kom ombo'],
    'montaza palace': ['montazah palace', 'montaza', 'montazah'],
  };

  static const List<String> _famousPlaces = [
    'Great Pyramid of Giza',
    'Pyramids of Giza',
    'الأهرامات',
    'الاهرامات',
    'اهرامات الجيزة',
    'Great Sphinx of Giza',
    'أبو الهول',
    'Egyptian Museum',
    'Grand Egyptian Museum',
    'Cairo Tower',
    'Khan el-Khalili',
    'Citadel of Cairo',
    'Cairo Citadel',
    'Saladin Citadel',
    'Abdeen Palace',
    'Luxor Temple',
    'Karnak Temple',
    'Valley of the Kings',
    'Temple of Hatshepsut',
    'Temple of Edfu',
    'Temple of Kom Ombo',
    'Philae Temple',
    'Abu Simbel Temples',
    'Bibliotheca Alexandrina',
    'Citadel of Qaitbay',
    'Montaza Palace',
    'Catacombs of Kom El Shoqafa',
    'Siwa Oasis',
  ];

  static const Map<String, String> _cityNameMap = {
    'cairo': 'Cairo',
    'القاهرة': 'Cairo',
    'القاهره': 'Cairo',
    'قاهرة': 'Cairo',
    'قاهره': 'Cairo',
    'cairo egypt': 'Cairo',
    'cairo governorate': 'Cairo',
    'giza': 'Giza',
    'الجيزة': 'Giza',
    'الجيزه': 'Giza',
    'جيزة': 'Giza',
    'جيزه': 'Giza',
    'giza egypt': 'Giza',
    'giza governorate': 'Giza',
    'luxor': 'Luxor',
    'الأقصر': 'Luxor',
    'الاقصر': 'Luxor',
    'luxor governorate': 'Luxor',
    'al uqsur': 'Luxor',
    'karnak': 'Luxor',
    'old karnak': 'Luxor',
    'الكرنك': 'Luxor',
    'الكرنك القديم': 'Luxor',
    'aswan': 'Aswan',
    'أسوان': 'Aswan',
    'اسوان': 'Aswan',
    'aswan governorate': 'Aswan',
    'abu simbel': 'Aswan',
    'abu simbel city': 'Aswan',
    'مدينة ابو سمبل': 'Aswan',
    'مدينة أبو سمبل': 'Aswan',
    'شاش': 'Aswan',
    'philae': 'Aswan',
    'فيلة': 'Aswan',
    'فيله': 'Aswan',
    'alexandria': 'Alexandria',
    'alex': 'Alexandria',
    'الإسكندرية': 'Alexandria',
    'الاسكندرية': 'Alexandria',
    'اسكندرية': 'Alexandria',
    'alexandria governorate': 'Alexandria',
    'siwa': 'Siwa',
    'سيوة': 'Siwa',
    'matrouh': 'Matrouh',
    'marsa matrouh': 'Matrouh',
    'marsa matruh': 'Matrouh',
    'matrouh governorate': 'Matrouh',
    'dahab': 'Dahab',
    'دهب': 'Dahab',
    'sharm': 'Sharm El Sheikh',
    'sharm el sheikh': 'Sharm El Sheikh',
    'شرم': 'Sharm El Sheikh',
    'شرم الشيخ': 'Sharm El Sheikh',
    'south sinai': 'Sharm El Sheikh',
    'south sinai governorate': 'Sharm El Sheikh',
    'port said': 'Port Said',
    'بورسعيد': 'Port Said',
    'بور سعيد': 'Port Said',
    'suez': 'Suez',
    'السويس': 'Suez',
    'ismailia': 'Ismailia',
    'الإسماعيلية': 'Ismailia',
    'الاسماعيلية': 'Ismailia',
    'hurghada': 'Hurghada',
    'الغردقة': 'Hurghada',
    'غردقة': 'Hurghada',
    'red sea governorate': 'Hurghada',
    'red sea': 'Hurghada',
    'faiyum': 'Faiyum',
    'fayoum': 'Faiyum',
    'الفيوم': 'Faiyum',
    'minya': 'Minya',
    'المنيا': 'Minya',
    'sohag': 'Sohag',
    'سوهاج': 'Sohag',
    'qena': 'Qena',
    'قنا': 'Qena',
  };

  static const Map<String, ({double lat, double lng})> _cityCoordinates = {
    'Cairo': (lat: 30.0444, lng: 31.2357),
    'Giza': (lat: 29.9870, lng: 31.2118),
    'Luxor': (lat: 25.6872, lng: 32.6396),
    'Aswan': (lat: 24.0889, lng: 32.8998),
    'Alexandria': (lat: 31.2001, lng: 29.9187),
    'Hurghada': (lat: 27.2578, lng: 33.8116),
    'Sharm El Sheikh': (lat: 27.9158, lng: 34.3300),
    'Dahab': (lat: 28.4897, lng: 34.5093),
    'Siwa': (lat: 29.2032, lng: 25.5195),
    'Faiyum': (lat: 29.3084, lng: 30.8428),
    'Beheira': (lat: 30.8481, lng: 30.3436),
    'Matrouh': (lat: 31.3543, lng: 27.2373),
    'Port Said': (lat: 31.2653, lng: 32.3019),
    'Suez': (lat: 29.9668, lng: 32.5498),
    'Ismailia': (lat: 30.5965, lng: 32.2715),
    'Minya': (lat: 28.1099, lng: 30.7503),
    'Sohag': (lat: 26.5591, lng: 31.6957),
    'Qena': (lat: 26.1551, lng: 32.7160),
  };

  // ════════════════════════════════════════════════════════
  //  PUBLIC API
  // ════════════════════════════════════════════════════════

  Future<SearchResult> searchPlaces({
    required String query,
    String? cityId,
    String? cityName,
    int maxResults = 10,
  }) {
    return search(
      query: query,
      cityId: cityId,
      cityName: cityName,
      maxResults: maxResults,
    );
  }

  Future<SearchResult> search({
    required String query,
    String? cityId,
    String? cityName,
    int maxResults = 10,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return SearchResult.empty;

    if (_isUnsupportedUserQuery(trimmed)) {
      if (kDebugMode) {
        debugPrint('[SearchEngine] rejected unsupported query outside app categories: $trimmed');
      }
      return SearchResult(
        correctedQuery: trimmed,
        results: const [],
        suggestions: const [],
        resultSources: const [],
      );
    }

    final index = await _getIndex();
    final firebaseDocIds =
        index.map((e) => e.id.trim()).where((e) => e.isNotEmpty).toSet();

    final normalizedForSearch = PlaceSearchPipeline.normalizeSearchQuery(trimmed);

    PlaceSearchPipeline.debugLog(
      'search raw="$trimmed" normalized="$normalizedForSearch" '
      'firebaseIndex=${index.length}',
    );
    final corrected = _resolveCorrectedQuery(normalizedForSearch, index);
    final resolvedCityFromQuery = _resolveCity('$trimmed $corrected', null);
    final cityIntent = PlaceSearchPipeline.extractCityIntentFromQuery(trimmed) ??
        resolvedCityFromQuery;
    final selectedCityName = _isGlobalCitySelection(cityName) ? null : cityName?.trim();

    final listingMatch = _tryParseCategoryListingQuery(trimmed);
    final listingEffective = (listingMatch != null && !_isKnownSpecificPlacePhrase(trimmed))
        ? listingMatch
        : null;

    final detectedCategoryLoose = _detectCategory('$trimmed $corrected');
    final detectedCategory = listingEffective?.category ?? detectedCategoryLoose;

    String? effectiveCategoryCity;
    if (listingEffective != null) {
      final seg = listingEffective.citySegment.trim();
      effectiveCategoryCity = _canonicalCityName(seg) ?? _resolveCity(seg, null) ?? seg;
      if (effectiveCategoryCity.trim().toLowerCase() == 'egypt') {
        effectiveCategoryCity = null;
      }
    }
    effectiveCategoryCity ??= () {
      if ((cityIntent ?? '').trim().isNotEmpty) return cityIntent;
      if ((resolvedCityFromQuery ?? '').trim().isNotEmpty) {
        return resolvedCityFromQuery;
      }
      return selectedCityName;
    }();

    final isCategoryQuery = listingEffective != null ||
        (detectedCategoryLoose != null &&
            _isGenericCategoryQuery(
              trimmed,
              detectedCategoryLoose,
              effectiveCategoryCity,
              cityIntent: cityIntent,
            ));

    // IMPORTANT:
    // Selected/typed city filters only category searches (cafes/restaurants/hotels).
    // For place-name searches, search across Egypt so a place in another city can be found.
    final shouldUseCityFilter = isCategoryQuery &&
        (effectiveCategoryCity ?? '').trim().isNotEmpty;

    // If the query names a different city than the dropdown, do not filter by the stale cityId.
    var effectiveCityId = cityId;
    if (shouldUseCityFilter &&
        (cityIntent ?? '').trim().isNotEmpty &&
        (selectedCityName ?? '').trim().isNotEmpty &&
        _normalizeSearchText(cityIntent!) !=
            _normalizeSearchText(selectedCityName!)) {
      effectiveCityId = null;
    }

    // Category searches need more than the normal single-place result limit.
    // Example: "cafes in cairo" should return a useful list, not 3-4 items.
    final effectiveMaxResults = isCategoryQuery ? math.max(maxResults, 30) : maxResults;

    final filtered = _applyFilters(
      index,
      cityId: shouldUseCityFilter && (effectiveCityId ?? '').trim().isNotEmpty
          ? effectiveCityId
          : null,
      cityName: shouldUseCityFilter ? effectiveCategoryCity : null,
      category: isCategoryQuery ? detectedCategory : null,
    );

    final ranked = _rank(
      query: corrected,
      rawQuery: trimmed,
      landmarks: filtered,
      cityHint: shouldUseCityFilter
          ? effectiveCategoryCity
          : (cityIntent ?? resolvedCityFromQuery),
      categoryHint: isCategoryQuery ? detectedCategory : null,
    );

    var results = ranked.take(effectiveMaxResults).toList();
    final firebaseMatchesCount = ranked.length;

    // For generic category searches like "tourists in cairo", the user expects
    // all already-saved matching places from Firebase, not only items whose name
    // text matches the literal word "tourists". This also makes previously
    // searched/generated places appear immediately on the next search.
    if (isCategoryQuery && detectedCategory != null) {
      final savedCategoryResults = _savedCategoryResultsForQuery(
        index,
        category: detectedCategory,
        cityName: effectiveCategoryCity,
        cityId: effectiveCityId,
      );
      if (savedCategoryResults.isNotEmpty) {
        results = _mergeSearchResults(
          savedCategoryResults,
          results,
          trimmed,
        ).take(effectiveMaxResults).toList();
      }
    }

    if (isCategoryQuery &&
        detectedCategory != null &&
        _providerGeneratedCategories.contains(detectedCategory)) {
      // Category searches need breadth. Use BOTH providers:
      // 1) Nominatim multi-query for named businesses/chains.
      // 2) Overpass/Nearby as a secondary provider because it often has more POIs.
      // Overpass is allowed to fail/timeout, but it must not block the search.
      final categoryCity = effectiveCategoryCity ?? resolvedCityFromQuery ?? cityName ?? '';
      if (categoryCity.trim().isNotEmpty && results.length < effectiveMaxResults) {
        final generatedFromNominatimFuture = _generateCategoryFromNominatim(
          category: detectedCategory,
          cityName: categoryCity,
          rawQuery: trimmed,
          maxResults: effectiveMaxResults,
        );

        // Important: do NOT cut Overpass too early with Future.timeout.
        // Future.timeout does not cancel the underlying Overpass request; it only
        // returns [] early while Overpass continues working in the background.
        // That was why the log showed `final from all endpoints=99` later,
        // but the UI and background save only received 1 Nominatim result.
        // We wait for the provider result here so category searches can display
        // the full list of cafes/restaurants/hotels.
        final generatedFromNearbyFuture = _generateFromNearbyProvider(
          category: detectedCategory,
          cityName: categoryCity,
          rawQuery: trimmed,
          maxResults: effectiveMaxResults,
          saveResults: false,
        );

        final providerResults = await Future.wait<List<Landmark>>([
          generatedFromNominatimFuture,
          generatedFromNearbyFuture,
        ]);

        if (kDebugMode) {
          debugPrint(
            '[SearchEngine] category Nominatim results=${providerResults[0].length}, '
            'Overpass results=${providerResults[1].length} for "$trimmed"',
          );
        }

        var generated = _mergeSearchResults(
          providerResults[0],
          providerResults[1],
          trimmed,
        );

        var providerFallbackAttemptedCat = false;
        var aiFallbackAttemptedCat = false;

        // Category searches should not stop at only 1-2 useful results.
        // Order must stay: Firebase first, API/provider results second,
        // and Gemini only as the LAST fallback if both are still not enough.
        final minUsefulCategoryResults = math.min(effectiveMaxResults, 10);

        final combinedCategoryCount = _mergeSearchResults(
          results,
          generated,
          trimmed,
        ).length;

        if (combinedCategoryCount < minUsefulCategoryResults &&
            categoryCity.trim().isNotEmpty &&
            AppConfig.hasValidGeminiKey) {
          providerFallbackAttemptedCat = true;

          final ai = await _geminiSuggestCategoryPlaces(
            category: detectedCategory,
            cityName: categoryCity,
            rawQuery: trimmed,
            maxResults: effectiveMaxResults,
          );

          if (ai.isNotEmpty) {
            aiFallbackAttemptedCat = true;
            generated = _mergeSearchResults(
              generated,
              ai,
              trimmed,
            );
          }
        }

        if (generated.isNotEmpty) {
          var mergedGen = _mergeSearchResults(generated, results, trimmed)
              .take(effectiveMaxResults)
              .toList();
          if (detectedCategory == 'outing') {
            mergedGen = mergedGen.where(_outingResultAcceptableForCategorySearch).toList();
          }
          results = mergedGen;

          // Show results immediately, then save generated provider results in
          // Firebase in the background so the next search can load them from
          // cache/Firebase without depending on Overpass again.
          unawaited(_saveGeneratedResultsInBackground(
            generated,
            category: detectedCategory,
            cityName: categoryCity,
            rawQuery: trimmed,
          ));

          _clearIndex();
        }

        if (kDebugMode) {
          debugPrint(
            '[SearchPipeline] categoryProviders '
            'providerFallbackAttempted=$providerFallbackAttemptedCat '
            'aiFallbackAttempted=$aiFallbackAttemptedCat '
            'mergedGenerated=${generated.length}',
          );
        }
      }
    }

    results = _prioritizeExactQuery(results, trimmed).take(effectiveMaxResults).toList();

    // UI display rule:
    // Search result cards should use English names whenever we can resolve one,
    // even if the stored Firebase document has an Arabic/local name.
    // This keeps image search, hero tags, and card rendering stable.
    results = _withEnglishDisplayNames(results);

    final isNamedPlaceSearch = !isCategoryQuery;
    var fallbackGenerationAttempted = false;
    var providerFallbackAttempted = false;
    var aiFallbackAttempted = false;
    var savedToFirebase = false;
    var saveReason = 'n/a';
    var generatedValidityNote = 'n/a';

    var relevantMatches = results.length;
    var namedPlacePreStrictCount = 0;
    var strictMatches = 0;

    if (isNamedPlaceSearch) {
      namedPlacePreStrictCount = results.length;
      results = _filterNamedPlacesStrict(
        candidates: results,
        rawQuery: trimmed,
        cityIntent: cityIntent,
        maxKeep: effectiveMaxResults,
      );
      relevantMatches = results.length;
      strictMatches = results.length;
      if (kDebugMode) {
        debugPrint(
          '[SearchPipeline] namedPlacePreStrict=$namedPlacePreStrictCount '
          'namedPlaceStrict=${results.length}',
        );
      }
    } else if (isCategoryQuery && detectedCategory == 'outing') {
      results = results.where(_outingResultAcceptableForCategorySearch).toList();
      relevantMatches = results.length;
    }

    if (isNamedPlaceSearch && results.isEmpty) {
      fallbackGenerationAttempted = true;

      final logSelectedCity = cityName ?? '';
      final logCityIntent = cityIntent ?? '';
      PlaceSearchPipeline.debugLog(
        '[NamedFallback] started query="$trimmed" '
        'selectedCity="$logSelectedCity" cityIntent="$logCityIntent"',
      );

      // -----------------------------
      // Stage 1: provider/OSM/Wiki/Gemini (existing)
      // -----------------------------
      var generated = await _generateSinglePlaceFromProviders(
        query: corrected,
        rawQuery: trimmed,
        category: detectedCategory,
        selectedCityName: cityName,
        existingResults: const [],
      );

      PlaceSearchPipeline.debugLog(
        '[NamedFallback] providerResult=${generated == null ? 'null' : '${generated.name} / ${generated.city} / ${generated.category} / provider=${generated.sources?['provider'] ?? ''}'}',
      );

      if (generated != null &&
          (generated.sources?['provider'] ?? '').toString() == 'gemini_place_suggest') {
        aiFallbackAttempted = true;
        providerFallbackAttempted = true;
      } else if (generated == null) {
        providerFallbackAttempted = true;
      }

      // -----------------------------
      // Stage 2: second-stage AI draft fallback when provider stage failed
      // -----------------------------
      if (generated == null) {
        // City resolution: cityIntent wins, else dropdown cityName, else infer.
        var effectiveCity = (cityIntent ?? '').trim();
        if (effectiveCity.isEmpty) {
          effectiveCity = (cityName ?? '').trim();
        }
        if (effectiveCity.isEmpty) {
          // Infer from query text.
          effectiveCity = _resolveCity('$trimmed $corrected', null) ?? '';
        }

        // Final guard: never save under unknown when we have a selected context.
        // If we truly cannot resolve, we still allow AI draft but validation will reject.
        if (kDebugMode) {
          debugPrint(
            '[NamedFallback] stage2 cityResolved="$effectiveCity" (selectedCity="$logSelectedCity" cityIntent="$logCityIntent")',
          );
        }

        aiFallbackAttempted = true;

        // Detect category intent if the query includes a category word.
        final catIntent = detectedCategory;

        final aiDraft = await _geminiSuggestNamedPlace(
          rawQuery: trimmed,
          cityHint: effectiveCity.isNotEmpty ? effectiveCity : null,
          categoryHint: catIntent,
        );

        if (aiDraft != null) {
          // Validate against the original query tokens/name/aliases.
          final sem = SemanticScorer.scoreSingle(query: trimmed, landmark: aiDraft);
          final fuzzy = _looseNameScore(aiDraft.name, trimmed);
          final strictLike = _filterNamedPlacesStrict(
            candidates: [aiDraft],
            rawQuery: trimmed,
            cityIntent: cityIntent,
            maxKeep: 1,
          );

          // Confidence handling:
          // - If semantic/fuzzy is strong, accept for saving.
          // - Else downgrade to needsReview and allow persistence only if still passes validation.
          final confFromSources = (aiDraft.sources?['confidence'] ?? '').toString();
          final confNum = double.tryParse(confFromSources) ?? 0.0;
          final plausible = sem.score >= 2.6 || fuzzy >= 0.44;

          var validated = aiDraft;
          final willNeedReview = !(plausible && strictLike.isNotEmpty && confNum >= 0.42);

          validated = validated.copyWith(
            generatedBySearch: true,
            needsReview: willNeedReview,
            // keep category limited by provider normalization already done in generator.
            sources: {
              ...(validated.sources ?? const <String, dynamic>{}),
              'sourceMetadata': 'named_search_ai_draft_stage2',
              'confidence': confNum.toString(),
            },
          );

          final aiReason = willNeedReview
              ? 'low_confidence_but_plausible sem=${sem.score.toStringAsFixed(1)} fuzzy=${fuzzy.toStringAsFixed(2)} conf=$confNum'
              : 'high_confidence sem=${sem.score.toStringAsFixed(1)} fuzzy=${fuzzy.toStringAsFixed(2)} conf=$confNum';

          PlaceSearchPipeline.debugLog(
            '[NamedFallback] aiGenerated=true reason=$aiReason city=${validated.city}',
          );

          generatedValidityNote =
              'semantic=${sem.score.toStringAsFixed(1)} fuzzy=${fuzzy.toStringAsFixed(2)} $aiReason';

          // Persistence (still guarded by _safePersistAndReturn).
          // For low confidence, keep relaxNameRelevance=false so garbage fails validation.
          final relaxGemini =
              (validated.sources?['provider'] ?? '').toString() == 'gemini_place_suggest' && !willNeedReview;

          final saved = await _safePersistAndReturn(
            validated,
            rawQuery: trimmed,
            markGenerated: true,
            relaxNameRelevance: relaxGemini,
          );

          savedToFirebase = saved != null;
          saveReason = savedToFirebase
              ? 'persisted'
              : 'verification_or_validation_failed';

          PlaceSearchPipeline.debugLog(
            '[NamedFallback] accepted=${savedToFirebase ? 'true' : 'false'} reason=$saveReason savedToFirebase=$savedToFirebase docId=${saved?.id ?? ''}',
          );

          if (saved != null) {
            results = _mergeSearchResults([saved], const [], trimmed)
                .take(maxResults)
                .toList();
            _clearIndex();
          } else {
            // If saving failed, do not return random unrelated results.
            results = const [];
            generatedValidityNote = 'stage2_persist_failed';
          }
        } else {
          PlaceSearchPipeline.debugLog(
            '[NamedFallback] aiGenerated=false reason=no_gemini_named_place_result',
          );
          generatedValidityNote = 'no_provider_or_ai_result';
        }
      } else {
        // Stage 1 success: keep existing behavior.
        final sem = SemanticScorer.scoreSingle(query: trimmed, landmark: generated);
        final fuzzy = _looseNameScore(generated.name, trimmed);
        generatedValidityNote =
            'semantic=${sem.score.toStringAsFixed(1)} fuzzy=${fuzzy.toStringAsFixed(2)} ${sem.matchReason}';
        final relaxGemini =
            (generated.sources?['provider'] ?? '').toString() == 'gemini_place_suggest';
        final saved = await _safePersistAndReturn(
          generated,
          rawQuery: trimmed,
          markGenerated: true,
          relaxNameRelevance: relaxGemini,
        );
        savedToFirebase = saved != null;
        saveReason = savedToFirebase
            ? 'persisted'
            : 'verification_or_validation_failed';
        final finalPlace = saved ?? generated;
        results = _mergeSearchResults([finalPlace], const [], trimmed)
            .take(maxResults)
            .toList();
        _clearIndex();
      }

      final finalCityForLog = results.isNotEmpty
          ? results.first.city
          : (cityIntent ?? cityName ?? '');
      PlaceSearchPipeline.debugLog(
        '[NamedFallback] finalCity=${finalCityForLog ?? ''} finalCount=${results.length}',
      );
    }

    // Final safety: never return the same visible place twice.
    // This is especially important after a named-place fallback persists a
    // provider result into an existing admin-edited Firestore document.
    // The UI must receive the canonical saved document, not a transient
    // provider/local duplicate with the same visible name.
    results = _dedupeFinalSearchResults(results);

    final suggestions = await getHints(trimmed, cityName: cityName);


    final detectedCityForResponse = cityIntent ??
        _detectedCityFromResults(results, '$trimmed $corrected') ??
        resolvedCityFromQuery;

    if (kDebugMode) {
      debugPrint(
        '[SearchPipeline] originalQuery="$trimmed" '
        'normalizedQuery="$normalizedForSearch" '
        'selectedCity=${cityName ?? ''} '
        'cityIntent=${cityIntent ?? ''} '
        'categoryIntent=${detectedCategory ?? ''} '
        'isNamedPlaceSearch=$isNamedPlaceSearch '
        'isGenericCategoryQuery=$isCategoryQuery '
        'firebaseMatchesCount=$firebaseMatchesCount '
        'namedPlacePreStrict=$namedPlacePreStrictCount '
        'strictMatches=$strictMatches '
        'categoryMatches=${isCategoryQuery ? relevantMatches : 0} '
        'relevantMatches=$relevantMatches '
        'providerFallbackAttempted=$providerFallbackAttempted '
        'aiFallbackAttempted=$aiFallbackAttempted '
        'fallbackGenerationAttempted=$fallbackGenerationAttempted '
        'generatedValidity=$generatedValidityNote '
        'savedToFirebase=$savedToFirebase '
        'saveReason=$saveReason '
        'finalCount=${results.length} '
        'finalCity=${detectedCityForResponse ?? ''}',
      );
    }

    return SearchResult(
      correctedQuery: corrected,
      results: results,
      suggestions: suggestions,
      detectedCity: detectedCityForResponse,
      detectedCategory: detectedCategory,
      cityIntent: cityIntent,
      isGenericCategoryQuery: isCategoryQuery,
      resultSources: _tagResultSources(results, firebaseDocIds),
    );
  }

  static const Set<String> _namedPlaceStrictStopwords = {
    'the', 'a', 'an', 'of', 'in', 'on', 'at', 'to', 'for', 'and', 'or', 'near',
    'best', 'top', 'place', 'places', 'egypt', 'city', 'area', 'around',
    'مصر', 'في', 'من', 'على', 'و', 'ال',
  };

  List<String> _criticalTokensNamedPlace(String rawQuery) {
    final q = _normalizeSearchText(rawQuery);
    if (q.isEmpty) return [];
    return q
        .split(RegExp(r'\s+'))
        .map((e) => e.trim())
        .where((t) => t.length >= 3 && !_namedPlaceStrictStopwords.contains(t))
        .toList();
  }

  double _maxFuzzyAgainstNamedQuery(Landmark lm, String rawQuery) {
    var best = _looseNameScore(lm.name, rawQuery);
    final dn = lm.displayName.trim();
    if (dn.isNotEmpty) best = math.max(best, _looseNameScore(dn, rawQuery));
    final nn = lm.normalizedName.trim();
    if (nn.isNotEmpty) best = math.max(best, _looseNameScore(nn, rawQuery));
    for (final a in lm.aliases) {
      final t = a.trim();
      if (t.isNotEmpty) best = math.max(best, _looseNameScore(t, rawQuery));
    }
    return best;
  }

  double _criticalTokenCoverage(Landmark lm, List<String> critical) {
    if (critical.isEmpty) return 1.0;
    final hay = _normalizeSearchText(
      '${lm.name} ${lm.displayName} ${lm.normalizedName} ${lm.aliases.join(' ')}',
    );
    var hits = 0;
    for (final t in critical) {
      if (hay.contains(t)) hits++;
    }
    return hits / critical.length;
  }

  double _phraseCoverage(Landmark lm, String qNorm) {
    if (qNorm.length < 4) return 0;
    final n = _normalizeSearchText(
      '${lm.name} ${lm.displayName} ${lm.normalizedName}',
    );
    if (n.isEmpty) return 0;
    if (n.contains(qNorm) || qNorm.contains(n)) return 1.0;
    final qParts = qNorm.split(' ').where((e) => e.length > 2).toList();
    if (qParts.isEmpty) return 0;
    var hit = 0;
    for (final p in qParts) {
      if (n.contains(p)) hit++;
    }
    return hit / qParts.length;
  }

  /// Strict named-entity filter: rejects "same city / same category" matches
  /// that do not match the actual place name the user typed.
  List<Landmark> _filterNamedPlacesStrict({
    required List<Landmark> candidates,
    required String rawQuery,
    required String? cityIntent,
    required int maxKeep,
  }) {
    if (candidates.isEmpty) return candidates;

    final critical = _criticalTokensNamedPlace(rawQuery);
    final qNorm = _normalizeSearchText(rawQuery);
    final accepted = <Landmark>[];

    for (final lm in candidates) {
      final fuzzy = _maxFuzzyAgainstNamedQuery(lm, rawQuery);
      final critCov = _criticalTokenCoverage(lm, critical);
      final phrase = _phraseCoverage(lm, qNorm);

      final minCrit = critical.isEmpty
          ? 1.0
          : critical.length <= 2
              ? 1.0
              : 0.72;

      final strongName = fuzzy >= 0.78;
      final goodBundle =
          critCov >= minCrit && fuzzy >= 0.55 && (phrase >= 0.55 || fuzzy >= 0.66);
      final decentWithPhrase = fuzzy >= 0.62 && phrase >= 0.72;

      var pass = strongName || goodBundle || decentWithPhrase;

      if (pass && critical.length >= 2 && critCov < 0.45 && fuzzy < 0.72) {
        pass = false;
      }

      if (pass) {
        final cat = PlaceCategoryNormalizer.normalize(
          lm.category,
          contextText: lm.name,
        );
        if (cat == 'outing' &&
            !PlaceSearchPipeline.isVerifiedVisitorOutingLandmark(lm)) {
          pass = false;
        }
      }

      if (kDebugMode) {
        final reason = pass
            ? 'accepted'
            : 'rejected: need stronger name/phrase match for named-place query';
        debugPrint(
          '[NamedPlaceRelevance] query="$rawQuery" place="${lm.name}" '
          'fuzzy=${fuzzy.toStringAsFixed(3)} tokenCov=${critCov.toStringAsFixed(3)} '
          'phrase=${phrase.toStringAsFixed(3)} -> $reason',
        );
      }

      if (pass) accepted.add(lm);
    }

    return accepted.take(maxKeep).toList();
  }

  List<PlaceResultSource> _tagResultSources(
    List<Landmark> list,
    Set<String> firebaseDocIds,
  ) {
    return list.map((lm) {
      if (lm.generatedBySearch) {
        return PlaceResultSource.generatedBySearch;
      }
      final id = lm.id.trim();
      if (id.isNotEmpty &&
          !id.startsWith('overpass_') &&
          firebaseDocIds.contains(id)) {
        return PlaceResultSource.fromFirebase;
      }
      if (id.isEmpty || id.startsWith('overpass_')) {
        return PlaceResultSource.generatedBySearch;
      }
      return PlaceResultSource.fromFirebase;
    }).toList();
  }

  String? _detectedCityFromResults(List<Landmark> results, String queryText) {
    final q = _normalizeSearchText(queryText);

    for (final entry in _canonicalCityMap.entries) {
      final key = _normalizeSearchText(entry.key);
      if (key.isNotEmpty && (q == key || q.contains(key) || key.contains(q))) {
        return entry.value;
      }
    }

    for (final lm in results) {
      final raw =
          '${lm.name} ${lm.city} ${lm.address} ${lm.shortDescription} ${lm.description}';
      final canonicalFromText = _canonicalizeGeneratedCity(
        lm.city,
        query: raw,
      );

      if (canonicalFromText.trim().isNotEmpty &&
          canonicalFromText.trim().toLowerCase() != 'egypt') {
        return canonicalFromText;
      }

      final resolved = _resolveCity(raw, null);
      if ((resolved ?? '').trim().isNotEmpty &&
          resolved!.trim().toLowerCase() != 'egypt') {
        return resolved;
      }
    }

    return null;
  }

  Future<List<String>> getHints(String query, {String? cityName}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final key = '${trimmed.toLowerCase()}|${(cityName ?? '').toLowerCase()}';
    if (_lastHintKey == key) return _lastHints;

    final index = await _getIndex();
    final q = _normalizeSearchText(trimmed);
    final city = _isGlobalCitySelection(cityName)
        ? ''
        : (cityName ?? '').trim().toLowerCase();

    final candidates = <String>[];
    for (final lm in index) {
      if (city.isNotEmpty && lm.city.trim().toLowerCase() != city) continue;
      final text = _normalizeSearchText('${lm.name} ${lm.city} ${lm.category}');
      if (text.contains(q) || _looseNameScore(lm.name, trimmed) >= 0.35) {
        candidates.add(lm.name);
      }
    }

    for (final name in _famousPlaces) {
      if (_normalizeSearchText(name).contains(q) ||
          _looseNameScore(name, trimmed) >= 0.35) {
        candidates.add(name);
      }
    }

    final deduped = <String>[];
    final seen = <String>{};
    for (final item in candidates) {
      final clean = item.trim();
      if (clean.isEmpty) continue;
      final k = clean.toLowerCase();
      if (seen.add(k)) deduped.add(clean);
      if (deduped.length >= 6) break;
    }

    _lastHintKey = key;
    _lastHints = deduped;
    return deduped;
  }


  List<Landmark> _savedCategoryResultsForQuery(
    List<Landmark> index, {
    required String category,
    String? cityName,
    String? cityId,
  }) {
    final normalizedCategory = PlaceCategoryNormalizer.normalize(category);
    final cityText = _normalizeSearchText(cityName ?? '');
    final cityIdText = (cityId ?? '').trim().toLowerCase();

    bool cityMatches(Landmark lm) {
      if (cityText.isEmpty && cityIdText.isEmpty) return true;

      if (cityIdText.isNotEmpty && lm.cityId.trim().toLowerCase() == cityIdText) {
        return true;
      }

      final lmCity = _normalizeSearchText(lm.city);
      final lmText = _normalizeSearchText(
        '${lm.city} ${lm.address} ${lm.description} ${lm.shortDescription} ${lm.fullDescription}',
      );

      if (cityText.isNotEmpty) {
        if (lmCity == cityText) return true;
        if (lmText.contains(cityText)) return true;
        if (_isKnownSubLocalityForCity(lm.city, cityName ?? '')) return true;
        if (_isKnownRegionLocalityForLocation(lm.city, cityName ?? '')) return true;
        if (_isKnownSubLocalityForCity(lm.address, cityName ?? '')) return true;
        if (_isKnownRegionLocalityForLocation(lm.address, cityName ?? '')) return true;
      }

      return false;
    }

    final result = <Landmark>[];
    final seen = <String>{};

    for (final lm in index) {
      final lmCategory = PlaceCategoryNormalizer.normalize(
        lm.category,
        contextText: '${lm.name} ${lm.description} ${lm.shortDescription}',
      );
      if (lmCategory != normalizedCategory) continue;
      if (!cityMatches(lm)) continue;
      if (lm.name.trim().isEmpty) continue;
      if (_isBlockedNonPlaceResult(
        name: lm.name,
        displayName: '${lm.description} ${lm.shortDescription} ${lm.address}',
        category: lm.category,
      )) {
        continue;
      }
      if (normalizedCategory == 'outing' &&
          !PlaceSearchPipeline.isVerifiedVisitorOutingLandmark(lm)) {
        continue;
      }

      final key = _equivalenceKey(lm);
      if (seen.add(key)) result.add(lm);
    }

    result.sort((a, b) {
      final aq = _qualityScore(a);
      final bq = _qualityScore(b);
      if (bq != aq) return bq.compareTo(aq);
      return a.name.compareTo(b.name);
    });

    return result;
  }

  // ════════════════════════════════════════════════════════
  //  INDEX
  // ════════════════════════════════════════════════════════

bool _isKnownRegionLocalityForLocation(String text, String location) {
    final t = _normalizeSearchText(text);
    final l = _normalizeSearchText(location);

    if (t.isEmpty || l.isEmpty) return false;

    final regionMap = <String, List<String>>{
      'sinai': [
        'sinai',
        'south sinai',
        'north sinai',
        'sharm',
        'sharm el sheikh',
        'dahab',
        'taba',
        'nuweiba',
        'arish',
        'el arish',
        'ras sidr',
        'saint catherine',
        'st catherine',
        'tor sinai',
        'el tor',
        'شرم',
        'شرم الشيخ',
        'دهب',
        'طابا',
        'نويبع',
        'العريش',
        'رأس سدر',
        'سانت كاترين',
        'الطور',
        'سيناء',
        'جنوب سيناء',
        'شمال سيناء',
      ],
      'north coast': [
        'north coast',
        'sahel',
        'marina',
        'el alamein',
        'alamein',
        'sidi abdelrahman',
        'sidi abdel rahman',
        'marsa matrouh',
        'matrouh',
        'الساحل',
        'الساحل الشمالي',
        'العلمين',
        'مارينا',
        'سيدي عبد الرحمن',
        'مرسى مطروح',
        'مطروح',
      ],
      'red sea': [
        'red sea',
        'hurghada',
        'gouna',
        'el gouna',
        'sahl hasheesh',
        'safaga',
        'marsa alam',
        'makadi',
        'الغردقة',
        'الجونة',
        'سهل حشيش',
        'سفاجا',
        'مرسى علم',
        'البحر الاحمر',
        'البحر الأحمر',
      ],
    };

    for (final entry in regionMap.entries) {
      final region = entry.key;
      final aliases = entry.value.map(_normalizeSearchText).toList();

      final locationMatchesRegion =
          l.contains(region) || aliases.any((alias) => l.contains(alias));

      if (!locationMatchesRegion) continue;

      final textMatchesLocality =
          t.contains(region) || aliases.any((alias) => t.contains(alias));

      if (textMatchesLocality) return true;
    }

    return false;
  }

  Future<List<Landmark>> _getIndex() async {
    final now = DateTime.now();
    if (_index != null &&
        _indexTimestamp != null &&
        now.difference(_indexTimestamp!) < _indexTtl) {
      return _index!;
    }

    final list = await _firebase.getAllLandmarks();
    final valid = _filterAndNormalize(list);
    for (final lm in valid) {
      _cache.merge(lm);
    }
    _index = valid;
    _indexTimestamp = now;
    return valid;
  }

  void _clearIndex() {
    _index = null;
    _indexTimestamp = null;
    _lastHintKey = '';
    _lastHints = [];
  }

  Future<void> _saveGeneratedResultsInBackground(
    List<Landmark> landmarks, {
    required String category,
    required String cityName,
    required String rawQuery,
  }) async {
    final saveKey = '${category.trim().toLowerCase()}|${cityName.trim().toLowerCase()}|${rawQuery.trim().toLowerCase()}';
    if (!_backgroundSaveKeys.add(saveKey)) return;

    try {
      final clean = <Landmark>[];
      final seen = <String>{};

      for (final lm in landmarks) {
        if (lm.name.trim().isEmpty) continue;
        if (lm.city.trim().isEmpty || lm.city.trim().toLowerCase() == 'egypt') {
          continue;
        }
        if (lm.lat == 0 || lm.lng == 0) continue;
        if (!PlaceCategoryNormalizer.isAllowed(
          lm.category,
          contextText: '${lm.name} ${lm.description} ${lm.shortDescription}',
        )) {
          continue;
        }
        if (_isBlockedNonPlaceResult(
          name: lm.name,
          displayName: '${lm.description} ${lm.address}',
          category: lm.category,
        )) {
          continue;
        }
        if (PlaceCategoryNormalizer.normalize(category) == 'outing' &&
            !PlaceSearchPipeline.isVerifiedVisitorOutingLandmark(lm) &&
            !PlaceSearchPipeline.isVerifiedVisitorOutingCandidate(
              name: lm.name,
              displayName: '${lm.description} ${lm.address}',
              osmClass: (lm.sources?['osmClass'] ?? lm.sources?['class'] ?? '').toString(),
              osmType: (lm.sources?['osmCategory'] ?? lm.sources?['type'] ?? '').toString(),
            )) {
          continue;
        }

        if (!_isAcceptableCategoryResultName(
          category: category,
          name: lm.name,
          displayName: '${lm.description} ${lm.shortDescription} ${lm.address}',
          osmClass: (lm.sources?['provider'] ?? '').toString(),
          osmType: '${lm.sources?['providerCategory'] ?? ''} ${lm.sources?['osmCategory'] ?? ''} ${lm.sources?['osmClass'] ?? ''}',
        )) {
          continue;
        }

        final key = _equivalenceKey(lm);
        if (!seen.add(key)) continue;

        // Provider IDs like overpass_x are temporary UI IDs. Firestore will
        // create/merge the real document and return a proper doc id.
        clean.add(lm.copyWith(id: ''));
        if (clean.length >= 30) break;
      }

      if (clean.isEmpty) return;

      print('[SearchEngine] background saving category results=${clean.length} for "$rawQuery"');
      await _firebase.saveLandmarks(clean);
      _clearIndex();
    } catch (e) {
      print('[SearchEngine] background save category results error: $e');
    } finally {
      _backgroundSaveKeys.remove(saveKey);
    }
  }

  List<Landmark> _filterAndNormalize(List<Landmark> list) {
    final result = <Landmark>[];
    final seen = <String>{};

    for (final lm in list) {
      if (lm.hidden || lm.isDuplicate || lm.invalidPlace) continue;
      if (lm.name.trim().isEmpty) continue;
      if (_isUnsupportedPlaceText(
        '${lm.name} ${lm.category} ${lm.description} ${lm.shortDescription} ${lm.address}',
      )) {
        continue;
      }
      if (lm.city.trim().isEmpty || lm.city.trim().toLowerCase() == 'egypt') {
        continue;
      }
      if (!PlaceCategoryNormalizer.isAllowed(
        lm.category,
        contextText: '${lm.name} ${lm.description} ${lm.shortDescription}',
      )) {
        continue;
      }
      if (_isBlockedNonPlaceResult(
        name: lm.name,
        displayName: '${lm.description} ${lm.shortDescription} ${lm.address}',
        category: lm.category,
      )) {
        continue;
      }

      final normalizedLmCategory = PlaceCategoryNormalizer.normalize(
        lm.category,
        contextText: '${lm.name} ${lm.description} ${lm.shortDescription}',
      );
      if (_providerGeneratedCategories.contains(normalizedLmCategory) &&
          !_isAcceptableCategoryResultName(
            category: normalizedLmCategory,
            name: lm.name,
            displayName: '${lm.description} ${lm.shortDescription} ${lm.address}',
            osmClass: (lm.sources?['provider'] ?? '').toString(),
            osmType: '${lm.sources?['providerCategory'] ?? ''} ${lm.sources?['providerTypes'] ?? ''} ${lm.sources?['osmCategory'] ?? ''} ${lm.sources?['osmClass'] ?? ''}',
          )) {
        continue;
      }

      final key = _equivalenceKey(lm);
      if (seen.add(key)) result.add(lm);
    }

    return result;
  }

  // ════════════════════════════════════════════════════════
  //  FILTER + RANK
  // ════════════════════════════════════════════════════════

  List<Landmark> _applyFilters(
    List<Landmark> index, {
    String? cityId,
    String? cityName,
    String? category,
  }) {
    final cityIdLower = (cityId ?? '').trim().toLowerCase();
    final cityNameLower = (cityName ?? '').trim().toLowerCase();
    final categoryNormalized = category == null
        ? null
        : PlaceCategoryNormalizer.normalize(category);

    return index.where((lm) {
      if (lm.hidden || lm.isDuplicate || lm.invalidPlace) return false;
      if (cityIdLower.isNotEmpty && lm.cityId.trim().toLowerCase() != cityIdLower) {
        return false;
      }
      if (cityIdLower.isEmpty && cityNameLower.isNotEmpty) {
        if (lm.city.trim().toLowerCase() != cityNameLower) return false;
      }
      if (categoryNormalized != null) {
        final lmCat = PlaceCategoryNormalizer.normalize(
          lm.category,
          contextText: '${lm.name} ${lm.shortDescription} ${lm.description}',
        );
        if (lmCat != categoryNormalized) return false;
      }
      return true;
    }).toList();
  }

  List<Landmark> _rank({
    required String query,
    required String rawQuery,
    required List<Landmark> landmarks,
    String? cityHint,
    String? categoryHint,
  }) {
    final q = _normalizeSearchText(query);
    final raw = _normalizeSearchText(rawQuery);
    final city = _normalizeSearchText(cityHint ?? '');
    final category = categoryHint == null
        ? null
        : PlaceCategoryNormalizer.normalize(categoryHint);

    final scored = <({Landmark lm, double score})>[];

    for (final lm in landmarks) {
      final lmCategory = PlaceCategoryNormalizer.normalize(
        lm.category,
        contextText: '${lm.name} ${lm.shortDescription} ${lm.description}',
      );
      final name = _normalizeSearchText(lm.name);
      final desc = _normalizeSearchText(
        '${lm.shortDescription} ${lm.description} ${lm.fullDescription} ${lm.address}',
      );
      final aliasBlob = _normalizeSearchText(
        '${lm.normalizedName} ${lm.aliases.join(' ')}',
      );
      final lmCity = _normalizeSearchText(lm.city);

      var score = 0.0;

      score += _looseNameScore(lm.name, rawQuery) * 80;
      score += _looseNameScore(lm.name, query) * 60;

      if (name == raw || name == q) score += 120;
      if (name.contains(raw) || raw.contains(name)) score += 45;
      if (desc.contains(raw)) score += 12;
      if (aliasBlob.contains(raw) || aliasBlob.contains(q)) score += 38;

      final aliasScore = _aliasScore(raw, name);
      score += aliasScore * 40;

      if (category != null && lmCategory == category) score += 25;
      if (city.isNotEmpty && lmCity == city) score += 12;

      score += _qualityScore(lm);

      if (score >= 12 || category != null) {
        scored.add((lm: lm, score: score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((e) => e.lm).toList();
  }

  List<Landmark> _prioritizeExactQuery(List<Landmark> list, String query) {
    final q = _normalizeSearchText(query);
    final sorted = [...list];

    sorted.sort((a, b) {
      final an = _normalizeSearchText(a.name);
      final bn = _normalizeSearchText(b.name);

      final aExact = an == q;
      final bExact = bn == q;
      if (aExact && !bExact) return -1;
      if (bExact && !aExact) return 1;

      final aStrong = _isStrongMatch(a, query);
      final bStrong = _isStrongMatch(b, query);
      if (aStrong && !bStrong) return -1;
      if (bStrong && !aStrong) return 1;

      final aContains = an.contains(q) || q.contains(an);
      final bContains = bn.contains(q) || q.contains(bn);
      if (aContains && !bContains) return -1;
      if (bContains && !aContains) return 1;

      return _qualityScore(b).compareTo(_qualityScore(a));
    });

    return sorted;
  }

  List<Landmark> _mergeSearchResults(
    List<Landmark> primary,
    List<Landmark> secondary,
    String query,
  ) {
    final result = <Landmark>[];
    final seen = <String>{};

    void add(Landmark lm) {
      final key = _equivalenceKey(lm);
      if (seen.add(key)) result.add(lm);
    }

    for (final lm in primary) add(lm);
    for (final lm in secondary) add(lm);

    return _prioritizeExactQuery(result, query);
  }

  bool _isStrongMatch(Landmark lm, String query) {
    final name = _normalizeSearchText(lm.name);
    final q = _normalizeSearchText(query);
    if (name.isEmpty || q.isEmpty) return false;
    if (name == q) return true;
    if (name.contains(q) || q.contains(name)) return true;
    return _looseNameScore(lm.name, query) >= 0.72;
  }

  double _qualityScore(Landmark lm) {
    var score = 0.0;
    if (lm.imageUrl.trim().isNotEmpty) score += 3;
    score += math.min(lm.mediaUrls.length, 5) * 1.2;
    if (lm.lat != 0 && lm.lng != 0) score += 3;
    if (lm.rating > 0) score += math.min(lm.rating, 5);
    if (lm.shortDescription.trim().length > 50) score += 2;
    if (lm.fullDescription.trim().length > 150) score += 2;
    if ((lm.wikipediaUrl ?? '').trim().isNotEmpty) score += 2;
    return score;
  }

  double _aliasScore(String query, String name) {
    var best = 0.0;
    for (final entry in _aliases.entries) {
      final canonical = _normalizeSearchText(entry.key);
      final aliases = entry.value.map(_normalizeSearchText).toList();
      final all = [canonical, ...aliases];
      if (all.any((a) => a == query || a.contains(query) || query.contains(a))) {
        best = math.max(best, _looseNameScore(canonical, name));
      }
    }
    return best;
  }

  // ════════════════════════════════════════════════════════
  //  GENERATION PROVIDERS
  // ════════════════════════════════════════════════════════

  Future<Landmark?> _generateSinglePlaceFromProviders({
    required String query,
    required String rawQuery,
    String? category,
    String? selectedCityName,
    required List<Landmark> existingResults,
  }) async {
    Landmark? osm;
    try {
      osm = await _fetchOsmTextSearchLandmark(
        query: query,
        rawQuery: rawQuery,
        category: category,
        cityName: selectedCityName,
        existingResults: existingResults,
      );
    } on http.ClientException catch (e) {
      _cooldownProvider('nominatim_osm|${_normalizeSearchText(rawQuery)}');
      if (kDebugMode) {
        debugPrint('[SearchEngine] Nominatim ClientException (named fallback): $e');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SearchEngine] Nominatim error (named fallback): $e');
      }
    }
    if (osm != null) return osm;

    final wiki = await _fetchWikipediaLandmark(
      query: query,
      rawQuery: rawQuery,
      category: category,
      cityName: selectedCityName,
      existingResults: existingResults,
    );
    if (wiki != null) return wiki;

    final cityHint = selectedCityName ?? _resolveCity(rawQuery, null);
    return _geminiSuggestNamedPlace(
      rawQuery: rawQuery,
      cityHint: cityHint,
      categoryHint: category,
    );
  }

  Future<Landmark?> _fetchOsmTextSearchLandmark({
    required String query,
    required String rawQuery,
    String? category,
    String? cityName,
    required List<Landmark> existingResults,
  }) async {
    final coolKey = 'nominatim_osm|${_normalizeSearchText(rawQuery)}';
    if (_isProviderCoolingDown(coolKey)) {
      if (kDebugMode) {
        debugPrint('[SearchEngine] skip Nominatim OSM (cooldown) $coolKey');
      }
      return null;
    }
    try {
      // Do NOT force selected city here. Search across Egypt and use the
      // real city from OSM address/display_name for saving.
      final searchText = '$rawQuery Egypt';

      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'q': searchText,
        'countrycodes': 'eg',
        'addressdetails': '1',
        'extratags': '1',
        'namedetails': '1',
        'limit': '10',
      });

      final res = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'GeoGuideApp/1.0 (student-graduation-project)',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        print('[SearchEngine] OSM text search status=${res.statusCode}');
        return null;
      }

      final data = jsonDecode(res.body);
      if (data is! List || data.isEmpty) return null;

      Map<String, dynamic>? best;
      double bestScore = 0;

      for (final item in data) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final displayName = (map['display_name'] ?? map['name'] ?? '').toString();
        if (displayName.trim().isEmpty) continue;

        final classText = (map['class'] ?? '').toString();
        final typeText = (map['type'] ?? '').toString();
        final address = Map<String, dynamic>.from(map['address'] as Map? ?? {});
        final rawCity = _cityFromOsmAddress(address) ?? _resolveCity(displayName, null) ?? '';
        final finalCity = _canonicalizeGeneratedCity(
          rawCity,
          query: '$rawQuery $displayName',
        );

        if (finalCity.trim().isEmpty || finalCity.trim().toLowerCase() == 'egypt') {
          continue;
        }

        final expectedCity = _expectedCityForPlaceQuery(rawQuery);
        if (!_cityMatchesExpected(finalCity, expectedCity)) {
          print('[SearchEngine] OSM rejected wrong city for "$rawQuery": $finalCity expected=$expectedCity');
          continue;
        }

        final cleanName = _chooseGeneratedName(
          rawQuery: rawQuery,
          osmItem: map,
        );
        final inferredCategory = _strictCategoryForGeneratedPlace(
          requestedCategory: category,
          name: cleanName,
          displayName: displayName,
          osmClass: classText,
          osmType: typeText,
        );
        if (inferredCategory == null) continue;

        if (_isBlockedNonPlaceResult(
          name: cleanName,
          displayName: '$displayName $classText $typeText',
          category: inferredCategory,
        )) {
          print('[SearchEngine] rejected OSM non-place result: $cleanName');
          continue;
        }

        if (!_looksEgyptianPlace(displayName, finalCity)) continue;
        if (!_looksLikeUsablePlace(
          query: rawQuery,
          name: cleanName,
          displayName: displayName,
          osmClass: classText,
          osmType: typeText,
        )) {
          continue;
        }

        final score = _osmCandidateScore(
          query: rawQuery,
          name: cleanName,
          displayName: displayName,
          osmClass: classText,
          osmType: typeText,
          city: finalCity,
        );

        if (score > bestScore) {
          bestScore = score;
          best = map;
        }
      }

      if (best == null || bestScore < 0.58) {
        print('[SearchEngine] OSM rejected: no strong result for "$rawQuery" score=$bestScore');
        return null;
      }

      final displayName = (best['display_name'] ?? '').toString();
      final cleanName = _chooseGeneratedName(
        rawQuery: rawQuery,
        osmItem: best,
      );
      final lat = double.tryParse((best['lat'] ?? '').toString()) ?? 0;
      final lng = double.tryParse((best['lon'] ?? '').toString()) ?? 0;
      if (lat == 0 || lng == 0) return null;

      final address = Map<String, dynamic>.from(best['address'] as Map? ?? {});
      final rawCity = _cityFromOsmAddress(address) ?? _resolveCity(displayName, null) ?? '';
      final resolvedCity = _canonicalizeGeneratedCity(
        rawCity,
        query: '$rawQuery $displayName',
      );

      if (resolvedCity.trim().isEmpty || resolvedCity.trim().toLowerCase() == 'egypt') {
        return null;
      }

      final expectedCity = _expectedCityForPlaceQuery(rawQuery);
      if (!_cityMatchesExpected(resolvedCity, expectedCity)) {
        print('[SearchEngine] OSM rejected final wrong city for "$rawQuery": $resolvedCity expected=$expectedCity');
        return null;
      }

      final inferredCategory = _strictCategoryForGeneratedPlace(
        requestedCategory: category,
        name: cleanName,
        displayName: displayName,
        osmClass: (best['class'] ?? '').toString(),
        osmType: (best['type'] ?? '').toString(),
      );
      if (inferredCategory == null) return null;

      if (_isBlockedNonPlaceResult(
        name: cleanName,
        displayName: displayName,
        category: inferredCategory,
      )) {
        print('[SearchEngine] rejected generated non-place result: $cleanName');
        return null;
      }

      final landmark = Landmark(
        id: '',
        name: cleanName,
        cityId: '',
        city: resolvedCity,
        category: inferredCategory,
        description: displayName,
        shortDescription: displayName,
        fullDescription: '',
        history: '',
        imageUrl: '',
        mediaUrls: const [],
        lat: lat,
        lng: lng,
        address: displayName,
        rating: 0,
        openingHours: '',
        location: '$lat, $lng',
        ticketPrice: null,
        wikipediaUrl: null,
        createdAt: DateTime.now(),
        sources: {
          'provider': 'nominatim_osm',
          'osmId': (best['osm_id'] ?? '').toString(),
          'osmType': (best['osm_type'] ?? '').toString(),
          'osmClass': (best['class'] ?? '').toString(),
          'osmCategory': (best['type'] ?? '').toString(),
        },
      );

      if (_containsEquivalent(existingResults, landmark)) return null;
      return landmark;
    } on http.ClientException catch (e) {
      _cooldownProvider(coolKey);
      if (kDebugMode) {
        debugPrint('[SearchEngine] OSM text Nominatim ClientException: $e');
      }
      return null;
    } catch (e) {
      print('[SearchEngine] OSM text fallback error: $e');
      return null;
    }
  }

  Future<Landmark?> _fetchWikipediaLandmark({
    required String query,
    required String rawQuery,
    String? category,
    String? cityName,
    required List<Landmark> existingResults,
  }) async {
    try {
      final queries = <String>[
        rawQuery,
        query,
        '$rawQuery Egypt',
      ];

      final seen = <String>{};
      for (final q in queries) {
        final k = q.trim().toLowerCase();
        if (k.isEmpty || !seen.add(k)) continue;

        final result = await _wikipedia.search(q, cityName: null);
        if (result == null) continue;

        final textForCity = '${result.title} ${result.summary} ${result.fullText} $q $query $rawQuery';
        final canonicalCity =
            _resolveCity(textForCity, null) ?? _inferCityFromKnownPlace(textForCity);

        if ((canonicalCity ?? '').trim().isEmpty ||
            canonicalCity!.trim().toLowerCase() == 'egypt') {
          print('[SearchEngine] rejected wiki result with no city: ${result.title}');
          continue;
        }

        final expectedCity = _expectedCityForPlaceQuery(rawQuery);
        if (!_cityMatchesExpected(canonicalCity, expectedCity)) {
          print('[SearchEngine] rejected wiki wrong city for "$rawQuery": ${result.title} city=$canonicalCity expected=$expectedCity');
          continue;
        }

        final normalizedCategory = _strictCategoryFromText(
          requestedCategory: category,
          text: '${result.title} ${result.summary} ${result.fullText}',
        );
        if (normalizedCategory == null) continue;

        if (_isBlockedNonPlaceResult(
          name: result.title,
          displayName: '${result.summary} ${result.fullText}',
          category: normalizedCategory,
        )) {
          print('[SearchEngine] rejected wiki non-place result: ${result.title}');
          continue;
        }

        if (!_isEgyptianResult(
          title: result.title,
          description: '${result.summary} ${result.fullText}',
          cityName: canonicalCity,
          query: q,
        )) {
          print('[SearchEngine] rejected non-Egypt wiki result: ${result.title}');
          continue;
        }

        if (!_looksLikeUsablePlace(
          query: rawQuery,
          name: result.title,
          displayName: '${result.title} ${result.summary}',
          osmClass: '',
          osmType: '',
        )) {
          continue;
        }

        final landmark = Landmark(
          id: '',
          name: result.title.trim(),
          cityId: '',
          city: canonicalCity,
          category: normalizedCategory,
          description: result.summary.trim(),
          shortDescription: result.summary.trim(),
          fullDescription: result.fullText.trim(),
          history: result.fullText.trim(),
          imageUrl: '',
          mediaUrls: const [],
          lat: 0,
          lng: 0,
          address: canonicalCity,
          rating: 0,
          openingHours: '',
          location: '',
          ticketPrice: null,
          wikipediaUrl: result.pageUrl,
          createdAt: DateTime.now(),
          wikiEnrichedAt: DateTime.now(),
          sources: const {'provider': 'wikipedia'},
        );

        if (!PlaceCategoryNormalizer.isAllowed(
          landmark.category,
          contextText: landmark.name,
        )) {
          continue;
        }

        if (_containsEquivalent(existingResults, landmark)) continue;
        return landmark;
      }

      return null;
    } catch (e) {
      print('[SearchEngine] wikipedia fallback error: $e');
      return null;
    }
  }

  Future<List<Landmark>> _generateFromNearbyProvider({
    required String category,
    required String? cityName,
    required String rawQuery,
    required int maxResults,
    bool preferNameMatch = false,
    bool saveResults = true,
  }) async {
    final resolvedCity = _resolveCity(rawQuery, cityName) ?? cityName;
    if ((resolvedCity ?? '').trim().isEmpty) {
      print('[SearchEngine] provider skipped: no city for "$rawQuery"');
      return [];
    }

    final coords = await _resolveCityCoordinates(resolvedCity!);
    if (coords == null) {
      print('[SearchEngine] provider skipped: no coords for "$resolvedCity"');
      return [];
    }

    final nearbyCategories = _nearbyCategoriesFor(category);
    final places = await _nearby.getNearbyForCoordinates(
      lat: coords.lat,
      lng: coords.lng,
      categories: nearbyCategories,
      limit: maxResults * 3, cityName: '',
    );

    print('[SearchEngine] category Overpass raw places=${places.length} for "$rawQuery"');

    if (places.isEmpty) {
      return _generateCategoryFromNominatim(
        category: category,
        cityName: resolvedCity,
        rawQuery: rawQuery,
        maxResults: maxResults,
      );
    }

    final filteredPlaces = preferNameMatch
        ? places.where((p) => _isLooseNameMatch(p.name, rawQuery)).toList()
        : places;

    final sourcePlaces = filteredPlaces.isNotEmpty ? filteredPlaces : places;

    final generated = <Landmark>[];
    for (final place in sourcePlaces) {
      final normalizedCategory = _normalizeProviderCategory(
        requestedCategory: category,
        providerCategory: place.category,
        providerTypes: place.types,
        name: place.name,
      );

      if (normalizedCategory != category) continue;
      if (place.name.trim().isEmpty) continue;
      if (place.lat == 0 || place.lng == 0) continue;
      if (_isBlockedNonPlaceResult(
        name: place.name,
        displayName: place.address,
        category: category,
      )) {
        continue;
      }

      if (!_isAcceptableCategoryResultName(
        category: category,
        name: place.name,
        displayName: '${place.address} ${place.category} ${place.types.join(' ')}',
        osmClass: place.category,
        osmType: place.types.join(' '),
      )) {
        continue;
      }

      final cleanProviderName = _normalizeGeneratedBusinessName(place.name);

      var heroUrl = place.imageUrl.trim();
      if (heroUrl.isNotEmpty) {
        final owners = await _firebase.findLandmarkIdsWithImageUrl(heroUrl);
        if (owners.isNotEmpty) {
          heroUrl = '';
        } else if (!_images.validateImageCandidateForPlace(
          url: heroUrl,
          metaText:
              '$cleanProviderName $resolvedCity $category ${place.address} ${place.types.join(" ")} $heroUrl',
          placeName: cleanProviderName,
          cityName: resolvedCity,
          category: category,
        )) {
          heroUrl = '';
        }
      }

      final landmark = Landmark(
        id: '',
        name: cleanProviderName,
        cityId: '',
        city: resolvedCity,
        category: category,
        description: place.address.trim(),
        shortDescription: place.address.trim().isNotEmpty
            ? place.address.trim()
            : '$category in $resolvedCity',
        fullDescription: '',
        history: '',
        imageUrl: heroUrl,
        mediaUrls: heroUrl.isNotEmpty ? [heroUrl] : const [],
        lat: place.lat,
        lng: place.lng,
        address: place.address.trim().isNotEmpty ? place.address.trim() : resolvedCity,
        rating: place.rating,
        openingHours: place.hasOpeningHours
            ? (place.isOpenNow ? 'Open now' : 'Opening hours available')
            : '',
        location: '${place.lat}, ${place.lng}',
        ticketPrice: null,
        wikipediaUrl: place.wikipediaUrl,
        createdAt: DateTime.now(),
        nearbyUpdatedAt: DateTime.now(),
        sources: {
          'provider': 'nearby_overpass',
          'providerPlaceId': place.placeId,
          'providerCategory': place.category,
          'providerTypes': place.types.join(','),
          'mapsUrl': place.mapsUrl,
          if (place.website != null) 'website': place.website,
          if (place.bookingUrl != null) 'bookingUrl': place.bookingUrl,
        },
      );

      if (saveResults) {
        final saved = await _safePersistAndReturn(
          landmark,
          rawQuery: rawQuery,
          markGenerated: true,
          relaxNameRelevance: true,
        );
        generated.add(saved ?? landmark);
      } else {
        // Category searches need to return many results fast. Saving every
        // Overpass POI one-by-one blocks the search long enough that the UI
        // only receives the small Nominatim subset. Return the places now;
        // full enrichment/save can happen later when a place is opened.
        generated.add(landmark.copyWith(
          id: 'overpass_${place.placeId}',
          imagesRefreshedAt: null,
          nearbyUpdatedAt: DateTime.now(),
        ));
      }
      if (generated.length >= maxResults) break;
    }

    return generated;
  }


  Future<List<Landmark>> _generateCategoryFromNominatim({
    required String category,
    required String cityName,
    required String rawQuery,
    required int maxResults,
  }) async {
    try {
      final city = _canonicalCityName(cityName) ?? cityName.trim();
      if (city.isEmpty) return [];

      final generated = <Landmark>[];
      final seen = <String>{};
      final queryTexts = _categoryNominatimQueries(category, city);

      for (final queryText in queryTexts) {
        if (generated.length >= maxResults) break;

        final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
          'format': 'jsonv2',
          'q': queryText,
          'countrycodes': 'eg',
          'addressdetails': '1',
          'extratags': '1',
          'namedetails': '1',
          'limit': '${math.max(maxResults * 5, 50)}',
        });

        late final http.Response res;
        try {
          res = await http.get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'GeoGuideApp/1.0 (student-graduation-project)',
            },
          ).timeout(const Duration(seconds: 8));
        } on http.ClientException catch (e) {
          _cooldownProvider('nominatim_cat|${_normalizeSearchText(queryText)}');
          if (kDebugMode) {
            debugPrint('[SearchEngine] category Nominatim ClientException: $e');
          }
          continue;
        }

        if (res.statusCode != 200) {
          print('[SearchEngine] category Nominatim status=${res.statusCode} query=$queryText');
          continue;
        }

        final data = jsonDecode(res.body);
        if (data is! List || data.isEmpty) continue;

        for (final item in data) {
          if (generated.length >= maxResults) break;
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final displayName = (map['display_name'] ?? map['name'] ?? '').toString();
          if (displayName.trim().isEmpty) continue;

          final lat = double.tryParse((map['lat'] ?? '').toString()) ?? 0;
          final lng = double.tryParse((map['lon'] ?? '').toString()) ?? 0;
          if (lat == 0 || lng == 0) continue;

          final address = Map<String, dynamic>.from(map['address'] as Map? ?? {});
          final rawCity = _cityFromOsmAddress(address) ?? _resolveCity(displayName, null) ?? city;
          final resolvedCity = _canonicalizeGeneratedCity(
            rawCity,
            query: '$rawQuery $displayName $city',
          );

          // For category searches, allow districts/localities inside the requested
          // city/governorate. Nominatim often returns district names rather than
          // the exact canonical city name.
          final expectedCity = _canonicalCityName(city) ?? city;
          final normalizedResolved = _normalizeSearchText(resolvedCity);
          final normalizedExpected = _normalizeSearchText(expectedCity);
          final normalizedDisplay = _normalizeSearchText(displayName);
          final cityOk = normalizedResolved == normalizedExpected ||
              normalizedDisplay.contains(normalizedExpected) ||
              _isKnownSubLocalityForCity(rawCity, expectedCity) ||
              _isKnownSubLocalityForCity(displayName, expectedCity);
          if (!cityOk) continue;

          var name = _nameFromOsmNamedetails(map);
          if (name.trim().isEmpty) {
            name = _cleanOsmDisplayName(displayName, rawQuery);
          }
          if (name.trim().isEmpty) continue;

          final classText = (map['class'] ?? '').toString();
          final typeText = (map['type'] ?? '').toString();

          // Category search must return real named businesses/places, not
          // generic words like "Caf", "Cafeteria", or street/area names.
          if (!_isAcceptableCategoryResultName(
            category: category,
            name: name,
            displayName: displayName,
            osmClass: classText,
            osmType: typeText,
          )) {
            continue;
          }

          final normalizedCategory = _strictCategoryForGeneratedPlace(
            requestedCategory: category,
            name: name,
            displayName: displayName,
            osmClass: classText,
            osmType: typeText,
          );
          if (normalizedCategory != category) continue;

          // Nominatim sometimes returns streets/neighbourhoods because a cafe or
          // restaurant appears inside the display_name. Do not create a cafe card
          // named "شارع العروبة" or a generic road/address result.
          final osmKind = _normalizeSearchText('$classText $typeText');
          final nameText = _normalizeSearchText(name);
          final isRoadOrAreaOnly = RegExp(
            r'\b(highway|road|residential|service|tertiary|secondary|primary|street|place|neighbourhood|neighborhood|suburb|quarter|administrative|locality)\b',
          ).hasMatch(osmKind);
          final nameItselfMatchesCategory = _textMatchesRequestedCategory(nameText, category);
          if (isRoadOrAreaOnly && !nameItselfMatchesCategory) continue;

          if (_isBlockedNonPlaceResult(
            name: name,
            displayName: '$displayName $classText $typeText',
            category: category,
          )) {
            continue;
          }

          final landmark = Landmark(
            id: '',
            name: name,
            cityId: '',
            city: expectedCity,
            category: category,
            description: displayName,
            shortDescription: displayName,
            fullDescription: '',
            history: '',
            imageUrl: '',
            mediaUrls: const [],
            lat: lat,
            lng: lng,
            address: displayName,
            rating: 0,
            openingHours: '',
            location: '$lat, $lng',
            ticketPrice: null,
            wikipediaUrl: null,
            createdAt: DateTime.now(),
            sources: {
              'provider': 'nominatim_category',
              'osmId': (map['osm_id'] ?? '').toString(),
              'osmType': (map['osm_type'] ?? '').toString(),
              'osmClass': classText,
              'osmCategory': typeText,
              'query': queryText,
            },
          );

          final key = _equivalenceKey(landmark);
          if (!seen.add(key)) continue;

          final saved = await _safePersistAndReturn(
            landmark,
            rawQuery: rawQuery,
            markGenerated: true,
            relaxNameRelevance: true,
          );
          generated.add(saved ?? landmark);
        }
      }

      return generated;
    } catch (e) {
      print('[SearchEngine] category Nominatim fallback error: $e');
      return [];
    }
  }

  List<String> _categoryNominatimQueries(String category, String city) {
    switch (category) {
      case 'hotel':
        return [
          'popular hotels in $city Egypt',
          'hotels in $city Egypt',
          'hotel in $city Egypt',
          'resorts in $city Egypt',
          'lodging in $city Egypt',
          'Hilton hotel in $city Egypt',
          'Marriott hotel in $city Egypt',
          'Steigenberger hotel in $city Egypt',
          'Four Seasons hotel in $city Egypt',
        ];
      case 'restaurant':
        return [
          'popular restaurants in $city Egypt',
          'restaurants in $city Egypt',
          'restaurant in $city Egypt',
          'dining in $city Egypt',
          'fast food in $city Egypt',
          'food court in $city Egypt',
          'McDonald\'s in $city Egypt',
          'KFC in $city Egypt',
          'Pizza Hut in $city Egypt',
          'Burger King in $city Egypt',
          'Koshary in $city Egypt',
          'Egyptian restaurant in $city Egypt',
        ];
      case 'cafe':
        return [
          'popular cafes in $city Egypt',
          'cafes in $city Egypt',
          'cafe in $city Egypt',
          'coffee shops in $city Egypt',
          'coffee in $city Egypt',
          'Starbucks in $city Egypt',
          'Costa Coffee in $city Egypt',
          'Cilantro Cafe in $city Egypt',
          'Beanos Cafe in $city Egypt',
          'Dunkin in $city Egypt',
          'Paul Cafe in $city Egypt',
          'Cafe in $city Egypt',
        ];
      case 'outing':
        return [
          'popular places in $city Egypt',
          'parks in $city Egypt',
          'gardens in $city Egypt',
          'malls in $city Egypt',
          'entertainment in $city Egypt',
          'tourist attractions in $city Egypt',
        ];
      case 'tourist':
      default:
        return [
          'popular tourist attractions in $city Egypt',
          'tourist attractions in $city Egypt',
          'landmarks in $city Egypt',
          'museums in $city Egypt',
          'historic sites in $city Egypt',
        ];
    }
  }


  String _normalizeGeneratedBusinessName(String name) {
    final raw = name.trim();
    final n = _normalizeSearchText(raw);
    const aliases = {
      'starbks': 'Starbucks',
      'starbucks coffee': 'Starbucks',
      'ستاربكس': 'Starbucks',
      'la poire': 'La Poire',
      'lapoire': 'La Poire',
      'لابوار': 'La Poire',
      'costa': 'Costa Coffee',
      'costa coffee': 'Costa Coffee',
      'كوستا': 'Costa Coffee',
      'dunkin': 'Dunkin',
      'dunkin donuts': 'Dunkin',
      'دانكن': 'Dunkin',
      'beanos': 'Beanos Cafe',
      'cilantro': 'Cilantro Cafe',
      'groppi': 'Groppi Cafe',
    };
    return aliases[n] ?? raw;
  }

  bool _isAcceptableCategoryResultName({
    required String category,
    required String name,
    required String displayName,
    required String osmClass,
    required String osmType,
  }) {
    final cat = PlaceCategoryNormalizer.normalize(category);
    final n = _normalizeSearchText(name);
    final d = _normalizeSearchText(displayName);
    final kind = _normalizeSearchText('$osmClass $osmType $displayName');
    if (n.isEmpty) return false;

    // Reject roads, areas, districts, addresses, and locality-only results.
    final roadOrAreaName = RegExp(
      r'\b(street|road|avenue|axis|bridge|square|district|area|zone|neighbourhood|neighborhood|quarter|suburb|city|village|town|route|highway)\b',
    ).hasMatch(n) ||
        RegExp(r'(شارع|طريق|ميدان|محور|كوبري|جسر|منطقه|منطقة|حي|حى|مدينه|مدينة|قريه|قرية|نزله|نزلة|المنطقة|المنطقه)').hasMatch(name);
    if (roadOrAreaName) return false;

    final roadOrAreaKind = RegExp(
      r'\b(highway|road|residential|service|tertiary|secondary|primary|street|place|neighbourhood|neighborhood|suburb|quarter|administrative|locality)\b',
    ).hasMatch(kind);
    if (roadOrAreaKind) return false;

    // Names like "Caf", "مقهي", "Cafeteria", "Espresso", "Coach" are too
    // generic/ambiguous for safe category results. They cause wrong photos and
    // get saved as fake cafes. This is a general common-noun filter, not a
    // place-by-place fallback.
    final weakBusinessNamesByCategory = <String, Set<String>>{
      'cafe': {
        'caf', 'cafe', 'cafes', 'cafeteria', 'coffee', 'coffee shop',
        'coffeehouse', 'espresso', 'moka', 'mocha', 'latte', 'cappuccino',
        'tea', 'tea house', 'coach', 'مقهي', 'مقهى', 'قهوه', 'قهوة',
        'كافيه', 'كافيهات', 'كافتيريا', 'كافيتريا'
      },
      'restaurant': {
        'restaurant', 'restaurants', 'resturant', 'resturants', 'dining',
        'food', 'food court', 'fast food', 'grill', 'مطعم', 'مطاعم', 'اكل',
        'أكل', 'طعام'
      },
      'hotel': {
        'hotel', 'hotels', 'resort', 'resorts', 'lodging', 'hostel',
        'guesthouse', 'motel', 'فندق', 'فنادق', 'منتجع', 'اوتيل', 'أوتيل', 'نزل'
      },
      'outing': {
        'park', 'garden', 'beach', 'mall', 'cinema', 'outing', 'حديقه',
        'حديقة', 'شاطئ', 'مول', 'سينما', 'خروجات', 'فسحه', 'فسحة'
      },
    };

    final weakNames = weakBusinessNamesByCategory[cat] ?? const <String>{};
    final tokens = n.split(' ').where((t) => t.trim().isNotEmpty).toList();
    if (n.length < 4) return false;
    if (tokens.length == 1 && tokens.first.length <= 3) return false;
    if (weakNames.contains(n)) return false;

    final trustedOneWordBrands = <String>{
      'starbucks', 'groppi', 'beanos', 'cilantro', 'dunkin', 'kfc',
      'mcdonalds', 'lapoire', 'costa'
    };
    if ((cat == 'cafe' || cat == 'restaurant' || cat == 'hotel') &&
        tokens.length == 1 &&
        !trustedOneWordBrands.contains(tokens.first) &&
        tokens.first.length <= 7) {
      return false;
    }

    final categoryKindOk = _osmKindMatchesRequestedCategory(kind, cat);
    final displayMatchesCategory = _textMatchesRequestedCategory(d, cat);

    // For business categories we only accept when the provider metadata proves
    // this is actually the requested kind. A specific-looking name alone is not
    // enough, because Overpass can return shops/streets with names like Coach.
    if (cat == 'cafe' || cat == 'restaurant' || cat == 'hotel') {
      if (!categoryKindOk && !displayMatchesCategory) return false;
    }

    // Tourist category searches such as "attractions in cairo" must return
    // real visitable places, not museum objects/exhibits/articles. Nominatim and
    // Wikipedia may return artifacts like "The two letters" because they are
    // inside a museum. Keep only place-like tourist results.
    if (cat == 'tourist') {
      if (_isNonPlaceTouristArtifact(name, displayName)) return false;

      final touristKindOk = _osmKindMatchesRequestedCategory(kind, cat);
      final touristNameLooksPlace = RegExp(
        r'\b(museum|palace|temple|citadel|mosque|church|tower|pyramid|sphinx|monument|fort|castle|tomb|park|garden|library|market|khan|street|square|viewpoint)\b',
      ).hasMatch(n) ||
          RegExp(r'(متحف|قصر|معبد|قلعة|مسجد|كنيسة|برج|هرم|أبو الهول|مقبرة|حديقة|خان|سوق|ميدان)').hasMatch(name);

      if (!touristKindOk && !touristNameLooksPlace) return false;
    }

    final categoryWords = <String>{
      ...weakNames,
      'egypt', 'cairo', 'giza', 'alexandria', 'luxor', 'aswan', 'street',
      'road', 'city', 'district', 'area', 'shop', 'store', 'branch',
      'شارع', 'طريق', 'القاهره', 'القاهرة', 'مصر'
    };
    final identityTokens = tokens
        .where((t) => t.length >= 4 && !categoryWords.contains(t))
        .toList();

    // Require a real identity token for business results. This avoids saving
    // pure labels like "مقهي" or "Cafeteria" while still allowing real names
    // such as Groppi, Starbucks, Beanos, Cilantro, etc.
    if ((cat == 'cafe' || cat == 'restaurant' || cat == 'hotel') &&
        identityTokens.isEmpty) {
      return false;
    }

    return true;
  }

  bool _isNonPlaceTouristArtifact(String name, String displayName) {
    final n = _normalizeSearchText(name);
    final d = _normalizeSearchText(displayName);
    final combined = '$n $d';

    // Reject object/exhibit/article names that are not visitable places.
    final artifactWords = RegExp(
      r'\b(letter|letters|tablet|papyrus|manuscript|ostracon|inscription|relief|statue|stela|stele|fragment|artifact|artefact|object|exhibit|sarcophagus|coin|painting|portrait|mummy|vase|seal|amulet|scroll|document|documents)\b',
    );
    final arabicArtifactWords = RegExp(
      r'(خطاب|خطابات|رسالة|رسائل|لوحة|بردية|مخطوط|مخطوطة|تمثال|نقش|قطعة|أثر|مومياء|تابوت|عملة|وثيقة|وثائق|معروض)',
    );

    final placeWords = RegExp(
      r'\b(museum|palace|temple|citadel|mosque|church|tower|pyramid|sphinx|monument|fort|castle|tomb|park|garden|library|market|khan|bazaar|square|viewpoint|site|ruins)\b',
    );
    final arabicPlaceWords = RegExp(
      r'(متحف|قصر|معبد|قلعة|مسجد|كنيسة|برج|هرم|أبو الهول|مقبرة|حديقة|خان|سوق|ميدان|موقع|أطلال)',
    );

    final looksArtifact = artifactWords.hasMatch(combined) ||
        arabicArtifactWords.hasMatch('$name $displayName');
    final looksPlace = placeWords.hasMatch(combined) ||
        arabicPlaceWords.hasMatch('$name $displayName');

    // "The two letters" / article-like result titles should not appear as Top Places.
    final articleLikeTitle = RegExp(r'\b(the|a|an)\s+\w+\s+\w+\b').hasMatch(n) && !looksPlace;

    return (looksArtifact && !looksPlace) || articleLikeTitle;
  }

  bool _osmKindMatchesRequestedCategory(String normalizedKind, String category) {
    switch (category) {
      case 'cafe':
        return RegExp(r'\b(amenity cafe|amenity coffee|amenity fast_food|amenity restaurant|cafe|coffee|food_court)\b')
            .hasMatch(normalizedKind);
      case 'restaurant':
        return RegExp(r'\b(amenity restaurant|amenity fast_food|amenity food_court|restaurant|fast_food|food_court)\b')
            .hasMatch(normalizedKind);
      case 'hotel':
        return RegExp(r'\b(tourism hotel|tourism guest_house|tourism hostel|tourism resort|hotel|guest_house|hostel|resort|motel)\b')
            .hasMatch(normalizedKind);
      case 'outing':
        return RegExp(r'\b(leisure park|leisure garden|tourism attraction|shop mall|amenity cinema|park|garden|mall|cinema|beach)\b')
            .hasMatch(normalizedKind);
      case 'tourist':
      default:
        return RegExp(r'\b(tourism attraction|tourism museum|historic|monument|archaeological_site|museum|attraction|viewpoint)\b')
            .hasMatch(normalizedKind);
    }
  }

  String _categoryNominatimKeyword(String category) {
    switch (category) {
      case 'hotel':
        return 'hotels';
      case 'restaurant':
        return 'restaurants';
      case 'cafe':
        return 'cafes';
      case 'outing':
        return 'parks attractions';
      case 'tourist':
      default:
        return 'tourist attractions';
    }
  }


  bool _isKnownSubLocalityForCity(String value, String expectedCity) {
    final text = _normalizeSearchText(value);
    final city = _normalizeSearchText(expectedCity);
    if (text.isEmpty || city.isEmpty) return false;

    const map = {
      'aswan': [
        'abu simbel', 'مدينة ابو سمبل', 'مدينة أبو سمبل', 'philae', 'file',
        'agilkia', 'shash', 'شاش', 'فيلة', 'فيله', 'aswan',
      ],
      'luxor': [
        'karnak', 'الكرنك', 'الكرنك القديم', 'luxor', 'الأقصر', 'الاقصر',
      ],
      'cairo': [
        'zamalek', 'downtown', 'maadi', 'heliopolis', 'nasr city', 'new cairo',
        'garden city', 'islamic cairo', 'old cairo', 'abdeen', 'الزمالك',
        'المعادي', 'مصر الجديدة', 'مدينة نصر', 'القاهرة', 'القاهره',
      ],
      'giza': [
        'giza', 'giza plateau', 'الجيزة', 'الجيزه', 'nazlet el samman',
        'kafr nassar', 'كفرة نصار', 'كفر نصار', 'haram', 'الهرم',
      ],
      'alexandria': [
        'alexandria', 'montaza', 'montazah', 'mandara', 'stanley', 'sidi gaber',
        'miami', 'المنتزه', 'المندرة', 'سيدي جابر', 'الإسكندرية', 'الاسكندرية',
      ],
    };

    final aliases = map[city] ?? const <String>[];
    for (final alias in aliases) {
      final a = _normalizeSearchText(alias);
      if (a.isNotEmpty && (text.contains(a) || a.contains(text))) return true;
    }
    return false;
  }


  // ════════════════════════════════════════════════════════
  //  CATEGORY GUARDRAILS
  // ════════════════════════════════════════════════════════

  bool _isUnsupportedUserQuery(String query) {
    final text = _normalizeSearchText(query);
    if (text.isEmpty) return false;

    // If the user is explicitly asking for one of the supported app categories,
    // do not block it here.
    if (_detectCategory(query) != null) return false;

    return _isUnsupportedPlaceText(text);
  }

  bool _isUnsupportedPlaceText(String value) {
    final text = _normalizeSearchText(value);
    if (text.isEmpty) return false;

    final hasSupportedSignal = RegExp(
      r'\b(tourist|attraction|landmark|monument|historic|historical|heritage|museum|temple|mosque|church|palace|castle|citadel|fort|pyramid|tomb|ruins|archaeological|gallery|tower|bridge|library|market|bazaar|souk|khan|hotel|resort|restaurant|restaurants|resturant|resturants|restraunt|restraunts|cafe|coffee|park|garden|zoo|beach|coast|island|oasis|mall|cinema|theater|theatre|stadium|aquarium)\b',
    ).hasMatch(text) ||
        RegExp(r'(متحف|معبد|مسجد|كنيسه|قصر|قلعه|هرم|اهرام|اثار|اثري|تاريخي|معلم|فندق|مطعم|كافيه|مقهي|حديقه|شاطئ|ساحل|جزيره|واحه|مول|سينما|سوق|خان)').hasMatch(text);

    if (hasSupportedSignal) return false;

    final unsupported = RegExp(
      r'\b(hospital|clinic|pharmacy|doctor|dentist|medical|school|university|college|academy|bank|atm|embassy|consulate|police|station|court|courthouse|government|ministry|office|company|factory|warehouse|supermarket|grocery|shop|store|airport|bus station|train station|metro station|gas station|fuel|parking|garage|real estate|apartment|residential|post office|telecom|mobile shop|car repair|workshop)\b',
    ).hasMatch(text) ||
        RegExp(r'(مستشفي|مستشفى|عياده|صيدليه|طبيب|مدرسه|جامعة|جامعه|كلية|كليه|بنك|سفاره|قنصليه|شرطه|محكمه|حكومه|وزارة|وزاره|مكتب|شركه|مصنع|مخزن|سوبرماركت|محل|متجر|مطار|محطه|بنزين|جراج|عقارات|سكني|بريد)').hasMatch(text);

    return unsupported;
  }

  String? _strictCategoryForGeneratedPlace({
    required String? requestedCategory,
    required String name,
    required String displayName,
    required String osmClass,
    required String osmType,
  }) {
    if (requestedCategory != null) {
      final normalizedRequested = PlaceCategoryNormalizer.normalize(requestedCategory);
      if (!_providerGeneratedCategories.contains(normalizedRequested)) return null;

      final text = _normalizeSearchText('$name $displayName $osmClass $osmType');
      if (_textMatchesRequestedCategory(text, normalizedRequested)) {
        return normalizedRequested;
      }

      return null;
    }

    final text = _normalizeSearchText('$name $displayName $osmClass $osmType');
    if (_isUnsupportedPlaceText(text)) return null;

    // Tourist must win before outing, because museums/palaces/temples are
    // tourist places even if OSM says attraction/place/building.
    if (RegExp(
      r'\b(tourism|attraction|landmark|monument|historic|historical|heritage|museum|temple|mosque|church|palace|castle|citadel|fort|pyramid|tomb|ruins|archaeological|gallery|tower|library|marketplace|market|bazaar|souk|khan)\b',
    ).hasMatch(text) ||
        RegExp(r'(متحف|متاحف|معبد|مسجد|كنيسه|قصر|قلعه|هرم|اهرام|اثار|اثري|تاريخي|معلم|سوق|خان)').hasMatch(text)) {
      return 'tourist';
    }

    if (RegExp(r'\b(hotel|resort|hostel|guesthouse|motel|lodging|accommodation)\b').hasMatch(text) ||
        RegExp(r'(فندق|فنادق|منتجع|اوتيل|أوتيل|نزل)').hasMatch(text)) {
      return 'hotel';
    }

    if (RegExp(r'\b(restaurant|restaurants|resturant|resturants|restraunt|restraunts|dining|food|grill|seafood|eatery|bistro|fast food|food court)\b').hasMatch(text) ||
        RegExp(r'(مطعم|مطاعم|اكل|أكل|طعام)').hasMatch(text)) {
      return 'restaurant';
    }

    if (RegExp(r'\b(cafe|cafes|coffee|cafeteria|tea house|bakery|patisserie)\b').hasMatch(text) ||
        RegExp(r'(كافيه|كافيهات|كافتريا|كافيتريا|قهوه|مقهي|مقهى)').hasMatch(text)) {
      return 'cafe';
    }

    if (RegExp(
      r'\b(outing|park|garden|zoo|aquarium|mall|shopping|cinema|theater|theatre|stadium|amusement|beach|coast|corniche|island|oasis|leisure|natural|recreation|entertainment|playground)\b',
    ).hasMatch(text) ||
        RegExp(r'(خروجات|فسح|فسحه|ترفيه|حديقه|حدائق|شاطئ|ساحل|كورنيش|جزيره|واحه|مول|سينما|ملاهي|تسوق)').hasMatch(text)) {
      if (isVerifiedVisitorOutingCandidate(
        name: name,
        displayName: displayName,
        osmClass: osmClass,
        osmType: osmType,
      )) {
        return 'outing';
      }
    }

    // OSM sometimes marks valid famous areas as place/neighbourhood without a
    // tourism tag. Accept only if the name itself has a travel/outing signal.
    if (RegExp(r'\b(place|neighbourhood|neighborhood|quarter|suburb|pedestrian|square)\b').hasMatch(text)) {
      final nameOnly = _normalizeSearchText(name);
      if (RegExp(r'\b(khan|souk|bazaar|market|palace|museum|temple|citadel|tower|park|garden|beach|coast|oasis|island)\b').hasMatch(nameOnly) ||
          RegExp(r'(خان|سوق|متحف|معبد|قصر|قلعه|برج|حديقه|شاطئ|ساحل|واحه|جزيره)').hasMatch(nameOnly)) {
        return RegExp(r'\b(park|garden|beach|coast|oasis|island)\b').hasMatch(nameOnly)
            ? 'outing'
            : 'tourist';
      }
    }

    return null;
  }

  bool isVerifiedVisitorOutingCandidate({
    required String name,
    required String displayName,
    required String osmClass,
    required String osmType,
  }) {
    final text = _normalizeSearchText('$name $displayName $osmClass $osmType');
    if (text.isEmpty) return false;

    final kind = _normalizeSearchText('$osmClass $osmType');
    final hasOutingSignal = _textMatchesRequestedCategory(text, 'outing');
    final kindMatches = _osmKindMatchesRequestedCategory(kind, 'outing');
    if (!hasOutingSignal && !kindMatches) return false;

    final isRoadOrAreaOnly = RegExp(
      r'\b(highway|road|residential|service|tertiary|secondary|primary|street|place|neighbourhood|neighborhood|suburb|quarter|administrative|locality)\b',
    ).hasMatch(text);
    if (isRoadOrAreaOnly &&
        !RegExp(r'\b(park|garden|zoo|aquarium|mall|shopping|cinema|theater|theatre|stadium|amusement|beach|coast|corniche|island|oasis|playground)\b')
            .hasMatch(text)) {
      return false;
    }

    return true;
  }

  bool _textMatchesRequestedCategory(String text, String category) {
    switch (category) {
      case 'hotel':
        return RegExp(r'\b(hotel|hotels|resort|hostel|guesthouse|motel|lodging|accommodation)\b').hasMatch(text) ||
            RegExp(r'(فندق|فنادق|منتجع|اوتيل|أوتيل|نزل)').hasMatch(text);
      case 'restaurant':
        return RegExp(r'\b(restaurant|restaurants|resturant|resturants|restraunt|restraunts|dining|food|grill|seafood|eatery|bistro|fast food|food court)\b').hasMatch(text) ||
            RegExp(r'(مطعم|مطاعم|اكل|أكل|طعام)').hasMatch(text);
      case 'cafe':
        return RegExp(r'\b(cafe|cafes|coffee|cafeteria|tea house|bakery|patisserie)\b').hasMatch(text) ||
            RegExp(r'(كافيه|كافيهات|كافتريا|كافيتريا|قهوه|مقهي|مقهى)').hasMatch(text);
      case 'outing':
        return RegExp(r'\b(outing|park|garden|zoo|aquarium|mall|shopping|cinema|theater|theatre|stadium|amusement|beach|coast|corniche|island|oasis|leisure|natural|recreation|entertainment|playground)\b').hasMatch(text) ||
            RegExp(r'(خروجات|فسح|فسحه|ترفيه|حديقه|حدائق|شاطئ|ساحل|كورنيش|جزيره|واحه|مول|سينما|ملاهي|تسوق)').hasMatch(text);
      case 'tourist':
        return RegExp(r'\b(tourism|attraction|landmark|monument|historic|historical|heritage|museum|temple|mosque|church|palace|castle|citadel|fort|pyramid|tomb|ruins|archaeological|gallery|tower|library|marketplace|market|bazaar|souk|khan)\b').hasMatch(text) ||
            RegExp(r'(متحف|متاحف|معبد|مسجد|كنيسه|قصر|قلعه|هرم|اهرام|اثار|اثري|تاريخي|معلم|سوق|خان)').hasMatch(text);
      default:
        return false;
    }
  }


  String? _strictCategoryFromText({
    required String? requestedCategory,
    required String text,
  }) {
    if (requestedCategory != null) {
      final normalized = PlaceCategoryNormalizer.normalize(
        requestedCategory,
        contextText: text,
      );
      return _providerGeneratedCategories.contains(normalized) ? normalized : null;
    }

    return _strictCategoryForGeneratedPlace(
      requestedCategory: null,
      name: text,
      displayName: text,
      osmClass: '',
      osmType: '',
    );
  }

  // ════════════════════════════════════════════════════════
  //  STRICT PLACE VALIDATION
  // ════════════════════════════════════════════════════════

  bool _isBlockedNonPlaceResult({
    required String name,
    required String displayName,
    required String category,
  }) {
    final text = _normalizeSearchText('$name $displayName $category');
    final nameText = _normalizeSearchText('$name $category');

    // Block obvious events/incidents based mainly on the result title/name.
    // Do not scan the whole Wikipedia body for words like "war" or "death",
    // because real tourist places often mention historical events.
    final hasDangerEvent = RegExp(
      r'\b(attack|attacks|terrorist|terrorism|bombing|incident|massacre|battle|war|revolution|protest|riot|accident|crash|disaster|death|murder|assassination|explosion|shooting|earthquake|flood)\b',
    ).hasMatch(nameText);
    if (hasDangerEvent) return true;

    final protectedPlace = RegExp(
      r'\b(sphinx|pyramid|pyramids|museum|temple|palace|citadel|mosque|church|monument|landmark|statue|tomb|ruins|archaeological|heritage|attraction|stadium|tower|bridge|library|park|garden|beach|hotel|restaurant|cafe|oasis|island)\b',
    ).hasMatch(text);
    if (protectedPlace) return false;

    const blocked = [
      'attack',
      'attacks',
      'terrorist',
      'terrorism',
      'bombing',
      'incident',
      'massacre',
      'battle',
      'war',
      'revolution',
      'protest',
      'riot',
      'accident',
      'crash',
      'disaster',
      'death',
      'murder',
      'assassination',
      'explosion',
      'shooting',
      'fire',
      'earthquake',
      'flood',
      'april',
      'january',
      'february',
      'march',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
      'يناير',
      'فبراير',
      'مارس',
      'ابريل',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'اغسطس',
      'أغسطس',
      'سبتمبر',
      'اكتوبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];

    if (blocked.any((w) => text.contains(w))) return true;

    final hasYear = RegExp(r'\b(18|19|20)\d{2}\b').hasMatch(text);
    final hasRealPlaceType = RegExp(
      r'\b(museum|palace|temple|mosque|church|citadel|castle|fort|pyramid|pyramids|sphinx|tomb|park|garden|beach|hotel|restaurant|cafe|library|bridge|tower|island|oasis|monument|landmark|statue|archaeological|ruins|heritage|attraction|stadium)\b',
    ).hasMatch(text);

    if (hasYear && !hasRealPlaceType) return true;

    return false;
  }

  bool _looksEgyptianPlace(String displayName, String city) {
    final text = _normalizeSearchText('$displayName $city');
    return text.contains('egypt') ||
        text.contains('مصر') ||
        _resolveCity(text, null) != null ||
        _inferCityFromKnownPlace(text) != null;
  }

  bool _looksLikeUsablePlace({
    required String query,
    required String name,
    required String displayName,
    required String osmClass,
    required String osmType,
  }) {
    final q = _normalizeSearchText(query);
    final n = _normalizeSearchText(name);
    final text = _normalizeSearchText('$name $displayName $osmClass $osmType');

    if (q.isEmpty || n.isEmpty) return false;

    if (_isBlockedNonPlaceResult(
      name: name,
      displayName: displayName,
      category: '$osmClass $osmType',
    )) {
      return false;
    }

    if (!_subtypeMatchesExpected(
      query: query,
      name: name,
      displayName: displayName,
      osmClass: osmClass,
      osmType: osmType,
    )) {
      return false;
    }

    if (n == q || n.contains(q) || q.contains(n)) return true;

    final qTokens = _importantTokens(q);
    final textTokens = _importantTokens(text);
    if (qTokens.isEmpty || textTokens.isEmpty) return false;

    final common = qTokens.intersection(textTokens).length;
    final ratio = common / math.max(qTokens.length, 1);

    final hasStrongNameSimilarity = _looseNameScore(name, query) >= 0.58 ||
        _looseNameScore(displayName, query) >= 0.58;

    final isKnownPlaceType = RegExp(
      r'\b(tourism|attraction|historic|heritage|museum|temple|mosque|church|palace|castle|citadel|fort|pyramid|tomb|ruins|archaeological|park|garden|beach|coast|oasis|island|hotel|restaurant|cafe|amenity|tourism|natural|leisure|building|marketplace|market|bazaar|souk|khan|place|neighbourhood|neighborhood|quarter|suburb|pedestrian|square)\b',
    ).hasMatch(_normalizeSearchText('$osmClass $osmType $displayName'));

    return isKnownPlaceType && (ratio >= 0.5 || hasStrongNameSimilarity);
  }

  double _osmCandidateScore({
    required String query,
    required String name,
    required String displayName,
    required String osmClass,
    required String osmType,
    required String city,
  }) {
    final q = _normalizeSearchText(query);
    final n = _normalizeSearchText(name);
    final d = _normalizeSearchText(displayName);
    var score = 0.0;

    if (!_subtypeMatchesExpected(
      query: query,
      name: name,
      displayName: displayName,
      osmClass: osmClass,
      osmType: osmType,
    )) {
      score -= 2.0;
    }

    final expectedCity = _expectedCityForPlaceQuery(query);
    if (!_cityMatchesExpected(city, expectedCity)) {
      score -= 2.0;
    }

    if (n == q) score += 2.0;
    if (n.contains(q) || q.contains(n)) score += 1.2;
    score += _looseNameScore(name, query);
    score += _looseNameScore(displayName, query) * 0.7;

    final qTokens = _importantTokens(q);
    final dTokens = _importantTokens(d);
    if (qTokens.isNotEmpty) {
      score += qTokens.intersection(dTokens).length / qTokens.length;
    }

    final osm = _normalizeSearchText('$osmClass $osmType');
    if (RegExp(r'\b(tourism|historic|heritage|museum|temple|palace|castle|attraction|amenity|leisure|natural)\b')
        .hasMatch(osm)) {
      score += 0.35;
    }

    if (_resolveCity('$displayName $city', null) != null) score += 0.25;

    return score;
  }

  Set<String> _importantTokens(String text) {
    const stop = {
      'the', 'a', 'an', 'of', 'in', 'on', 'at', 'to', 'for', 'and', 'or',
      'egypt', 'eg', 'governorate', 'city', 'place', 'tourist', 'historic',
      'el', 'al', 'de', 'street', 'road', 'area', 'district',
      'مصر', 'في', 'من', 'الى', 'إلى', 'على', 'و', 'ال',
    };
    return _normalizeSearchText(text)
        .split(RegExp(r'\s+'))
        .map((e) => e.trim())
        .where((e) => e.length >= 3 && !stop.contains(e))
        .toSet();
  }

  // ════════════════════════════════════════════════════════
  //  CATEGORY PROVIDER HELPERS
  // ════════════════════════════════════════════════════════

  List<String> _nearbyCategoriesFor(String category) {
    switch (category) {
      case 'hotel':
        return const ['hotel'];
      case 'restaurant':
        return const ['restaurant'];
      case 'cafe':
        return const ['cafe'];
      case 'outing':
        return const ['outing', 'park', 'garden', 'beach', 'mall'];
      case 'tourist':
      default:
        return const ['tourist'];
    }
  }

  String _normalizeProviderCategory({
    required String requestedCategory,
    required String providerCategory,
    required List<String> providerTypes,
    required String name,
  }) {
    final text = '$providerCategory ${providerTypes.join(' ')} $name';
    return PlaceCategoryNormalizer.normalize(text);
  }

  // ════════════════════════════════════════════════════════
  //  PERSISTENCE
  // ════════════════════════════════════════════════════════

  Future<Landmark?> _safePersistAndReturn(
    Landmark landmark, {
    required String rawQuery,
    bool markGenerated = false,
    bool relaxNameRelevance = false,
  }) async {
    try {
      if (landmark.name.trim().isEmpty) return null;
      if (landmark.city.trim().isEmpty || landmark.city.trim().toLowerCase() == 'egypt') {
        if (kDebugMode) {
          debugPrint('[SearchEngine] persist skipped: invalid city for ${landmark.name}');
        }
        return null;
      }
      if (_isBlockedNonPlaceResult(
        name: landmark.name,
        displayName: '${landmark.description} ${landmark.address}',
        category: landmark.category,
      )) {
        if (kDebugMode) {
          debugPrint('[SearchEngine] persist skipped non-place: ${landmark.name}');
        }
        return null;
      }

      final outingCat = PlaceCategoryNormalizer.normalize(
        landmark.category,
        contextText: landmark.name,
      );
      if (outingCat == 'outing' &&
          !PlaceSearchPipeline.isVerifiedVisitorOutingLandmark(landmark)) {
        if (kDebugMode) {
          debugPrint('[SearchEngine] persist skipped outing verification: ${landmark.name}');
        }
        return null;
      }

      if (!relaxNameRelevance) {
        final sem = SemanticScorer.scoreSingle(query: rawQuery, landmark: landmark);
        final fuzzy = _looseNameScore(landmark.name, rawQuery);
        if (sem.score < 3.2 && fuzzy < 0.42) {
          if (kDebugMode) {
            debugPrint(
              '[SearchEngine] persist skipped weak name match: ${landmark.name} '
              'semantic=${sem.score.toStringAsFixed(1)} fuzzy=${fuzzy.toStringAsFixed(2)}',
            );
          }
          return null;
        }
      }

      final canonicalName = _canonicalEnglishNameFromText(
        '${landmark.name} ${landmark.description} ${landmark.shortDescription} ${landmark.address} ${landmark.wikipediaUrl ?? ''}',
      );
      var base = canonicalName == null
          ? landmark
          : landmark.copyWith(name: canonicalName);

      base = PlaceSearchPipeline.prepareLandmarkForPersist(
        base,
        rawQuery: rawQuery,
        generatedBySearch: markGenerated,
      );

      if (!PlaceSearchPipeline.validatePlaceForFirebaseSave(base)) {
        PlaceSearchPipeline.debugLog(
          'persist skipped validation name=${base.name} city=${base.city} cat=${base.category}',
        );
        return null;
      }

      final id = await _firebase.saveLandmark(base);

      // Always return the canonical Firestore document after persistence.
      // saveLandmark may merge into an existing admin-edited document by
      // name/city. Returning the raw generated/provider landmark here can make
      // search show a same-name item that is not the real Home/Admin document.
      final fresh = await _firebase.getLandmarkById(id);
      final saved = fresh ?? base.copyWith(id: id);

      // Use put(), not merge(), because this is the canonical saved document
      // for the current search result. Smart merge may keep older richer text
      // and make the UI look stale after admin edits.
      _cache.put(saved);
      PlaceSearchPipeline.debugLog(
        'persisted id=$id name=${saved.name} normalized=${saved.normalizedName} refetched=${fresh != null}',
      );
      return saved;
    } catch (e) {
      print('[SearchEngine] persist failed for ${landmark.name}: $e');
      return null;
    }
  }

  bool _isTransientSearchResultId(String id) {
    final clean = id.trim().toLowerCase();
    if (clean.isEmpty) return true;
    return clean.startsWith('local_seed_') ||
        clean.startsWith('local_') ||
        clean.startsWith('seed_') ||
        clean.startsWith('overpass_') ||
        clean.startsWith('nominatim_') ||
        clean.startsWith('osm_') ||
        clean.startsWith('wiki_') ||
        clean.startsWith('provider_') ||
        clean.startsWith('gemini_');
  }

  int _finalSearchCandidateScore(Landmark lm) {
    var score = 0;
    final id = lm.id.trim();

    if (id.isNotEmpty && !_isTransientSearchResultId(id)) score += 10000;
    if (lm.sources != null && (lm.sources!['lastAdminEditAt'] ?? '').toString().trim().isNotEmpty) {
      score += 5000;
    }
    if (!lm.generatedBySearch) score += 1000;
    if (lm.imageUrl.trim().startsWith('http')) score += 200;
    score += lm.mediaUrls.where((u) => u.trim().startsWith('http')).length * 40;
    score += lm.shortDescription.trim().length.clamp(0, 250);
    score += lm.fullDescription.trim().length.clamp(0, 500);
    score += (lm.rating * 10).round();
    if (!lm.hidden && !lm.invalidPlace && !lm.isDuplicate) score += 100;
    return score;
  }

  String _finalSearchVisibleKey(Landmark lm) {
    final name = _normalizeSearchText(lm.name)
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'\b(the|of|el|al|egypt|cairo|giza)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final cat = PlaceCategoryNormalizer.normalize(
      lm.category,
      contextText: '${lm.name} ${lm.shortDescription} ${lm.description}',
    );

    final text = _normalizeSearchText('${lm.name} ${lm.shortDescription} ${lm.fullDescription}');
    final landmarkLike = cat == 'tourist' ||
        cat == 'outing' ||
        text.contains('citadel') ||
        text.contains('museum') ||
        text.contains('palace') ||
        text.contains('temple');

    if (landmarkLike) return name;
    return '$name|$cat|${_normalizeSearchText(lm.city)}';
  }

  List<Landmark> _dedupeFinalSearchResults(List<Landmark> input) {
    final byId = <String, Landmark>{};
    final ordered = <Landmark>[];

    for (final lm in input) {
      if (lm.name.trim().isEmpty) continue;
      final id = lm.id.trim();
      if (id.isNotEmpty && !_isTransientSearchResultId(id)) {
        final existing = byId[id];
        if (existing == null) {
          byId[id] = lm;
          ordered.add(lm);
        } else if (_finalSearchCandidateScore(lm) > _finalSearchCandidateScore(existing)) {
          byId[id] = lm;
          final idx = ordered.indexWhere((e) => e.id.trim() == id);
          if (idx >= 0) ordered[idx] = lm;
        }
      } else {
        ordered.add(lm);
      }
    }

    final byVisible = <String, Landmark>{};
    for (final lm in ordered) {
      final key = _finalSearchVisibleKey(lm);
      if (key.isEmpty) continue;
      final existing = byVisible[key];
      if (existing == null ||
          _finalSearchCandidateScore(lm) > _finalSearchCandidateScore(existing)) {
        byVisible[key] = lm;
      }
    }

    final result = byVisible.values.toList();
    result.sort((a, b) =>
        _finalSearchCandidateScore(b).compareTo(_finalSearchCandidateScore(a)));
    return result;
  }

  // ════════════════════════════════════════════════════════
  //  TEXT / CITY HELPERS
  // ════════════════════════════════════════════════════════

  String _resolveCorrectedQuery(String query, List<Landmark> index) {
    final q = _normalizeSearchText(query);
    if (q.isEmpty) return query.trim();

    final directCanonical = _canonicalEnglishNameFromText(query);
    if (directCanonical != null) return directCanonical;

    String best = query.trim();
    double bestScore = 0;

    for (final lm in index) {
      final score = _looseNameScore(lm.name, query);
      if (score > bestScore) {
        bestScore = score;
        best = lm.name;
      }
    }

    for (final name in _famousPlaces) {
      final score = _looseNameScore(name, query);
      if (score > bestScore) {
        bestScore = score;
        best = name;
      }
    }

    return bestScore >= 0.78 ? best : query.trim();
  }

  bool _hasFuzzyCategoryWord(String query, List<String> keywords) {
    final normalized = _normalizeSearchText(query);
    if (normalized.isEmpty) return false;

    final tokens = normalized
        .split(RegExp(r'\s+'))
        .map((e) => e.trim())
        .where((e) => e.length >= 3)
        .toList();

    for (final token in tokens) {
      for (final rawKeyword in keywords) {
        final keyword = _normalizeSearchText(rawKeyword);
        if (keyword.isEmpty) continue;

        if (token == keyword) return true;
        if (token.length >= 5 && (token.contains(keyword) || keyword.contains(token))) {
          return true;
        }

        final maxLen = math.max(token.length, keyword.length);
        if (maxLen < 5) continue;

        final distance = _levenshtein(token, keyword);
        final allowedDistance = maxLen <= 7 ? 1 : 2;
        if (distance <= allowedDistance) return true;
      }
    }

    return false;
  }

  String? _detectCategory(String query) {
    final lower = query.toLowerCase();

    if (_hasFuzzyCategoryWord(query, const ['hotel', 'hotels', 'hostel', 'resort']) ||
        lower.contains('hotel') ||
        lower.contains('hotels') ||
        lower.contains('hostel') ||
        lower.contains('resort') ||
        lower.contains('فندق') ||
        lower.contains('فنادق') ||
        lower.contains('اوتيل') ||
        lower.contains('أوتيل')) {
      return 'hotel';
    }

    if (_hasFuzzyCategoryWord(query, const ['restaurant', 'restaurants', 'resturant', 'restraunt', 'dining']) ||
        lower.contains('restaurant') ||
        lower.contains('restaurants') ||
        lower.contains('resturant') ||
        lower.contains('resturants') ||
        lower.contains('restraunt') ||
        lower.contains('restraunts') ||
        lower.contains('مطعم') ||
        lower.contains('مطاعم') ||
        lower.contains('food') ||
        lower.contains('eat') ||
        lower.contains('اكل') ||
        lower.contains('أكل')) {
      return 'restaurant';
    }

    if (_hasFuzzyCategoryWord(query, const ['cafe', 'cafes', 'coffee', 'cafeteria']) ||
        lower.contains('cafe') ||
        lower.contains('cafes') ||
        lower.contains('coffee') ||
        lower.contains('cafeteria') ||
        lower.contains('كافيه') ||
        lower.contains('كافيهات') ||
        lower.contains('كافتريا') ||
        lower.contains('كافيتريا') ||
        lower.contains('قهوة') ||
        lower.contains('مقهى')) {
      return 'cafe';
    }

    if (_hasFuzzyCategoryWord(query, const ['outing', 'outings', 'park', 'parks', 'garden', 'mall', 'cinema', 'beach']) ||
        lower.contains('outing') ||
        lower.contains('outings') ||
        lower.contains('park') ||
        lower.contains('parks') ||
        lower.contains('garden') ||
        lower.contains('mall') ||
        lower.contains('cinema') ||
        lower.contains('beach') ||
        lower.contains('coast') ||
        lower.contains('فسح') ||
        lower.contains('فسحة') ||
        lower.contains('خروجات') ||
        lower.contains('خروجة') ||
        lower.contains('حديقة') ||
        lower.contains('حدائق') ||
        lower.contains('مول') ||
        lower.contains('سينما') ||
        lower.contains('ساحل') ||
        lower.contains('شاطئ')) {
      return 'outing';
    }

    if (_hasFuzzyCategoryWord(query, const ['tourist', 'tourists', 'tourism', 'attraction', 'attractions', 'landmark', 'landmarks', 'museum', 'museums']) ||
        lower.contains('attraction') ||
        lower.contains('attractions') ||
        lower.contains('tourist') ||
        lower.contains('landmark') ||
        lower.contains('landmarks') ||
        lower.contains('museum') ||
        lower.contains('museums') ||
        lower.contains('historic') ||
        lower.contains('historical') ||
        lower.contains('archaeological') ||
        lower.contains('monument') ||
        lower.contains('temple') ||
        lower.contains('citadel') ||
        lower.contains('palace') ||
        lower.contains('mosque') ||
        lower.contains('church') ||
        lower.contains('مزار') ||
        lower.contains('مزارات') ||
        lower.contains('سياحي') ||
        lower.contains('سياحية') ||
        lower.contains('معلم') ||
        lower.contains('معالم') ||
        lower.contains('متحف') ||
        lower.contains('متاحف') ||
        lower.contains('أثري') ||
        lower.contains('اثري')) {
      return 'tourist';
    }

    return null;
  }

  bool _isGenericCategoryQuery(
    String query,
    String category,
    String? cityName, {
    String? cityIntent,
  }) {
    final normalized = _normalizeSearchText(query);
    final city = _normalizeSearchText(cityName ?? '');
    final cityFromQuery = _normalizeSearchText(_resolveCity(query, null) ?? '');
    final cityFromIntent = _normalizeSearchText(cityIntent ?? '');

    final tokensToRemove = <String>{
      ..._categoryWords(category),
      ..._categorySynonymsForGenericDetection(category),
      'in',
      'near',
      'around',
      'egypt',
      'في',
      'داخل',
      'قريب',
      'قريبة',
      if (city.isNotEmpty) ...city.split(' ').where((t) => t.length > 1),
      if (cityFromQuery.isNotEmpty) ...cityFromQuery.split(' ').where((t) => t.length > 1),
      if (cityFromIntent.isNotEmpty) ...cityFromIntent.split(' ').where((t) => t.length > 1),
    };

    final remaining = normalized
        .split(RegExp(r'\s+'))
        .where((t) => t.trim().isNotEmpty && !tokensToRemove.contains(t))
        .toList();

    // If the user wrote only category words, it is a generic category search.
    // If there are important remaining words, treat it as a specific place search.
    return remaining.isEmpty;
  }

  Set<String> _categorySynonymsForGenericDetection(String category) {
    switch (category) {
      case 'tourist':
        return {
          'tourist', 'tourists', 'tourist attraction', 'tourist attractions',
          'tourism', 'attraction', 'attractions', 'landmark', 'landmarks',
          'sight', 'sights', 'sightseeing', 'places', 'place',
          'مزارات', 'مزار', 'معالم', 'معلم', 'سياحي', 'سياحية'
        };
      case 'cafe':
        return {'cafe', 'cafes', 'coffee', 'coffee shop', 'coffee shops', 'cafeteria', 'كافيه', 'كافيهات', 'قهوة', 'مقهى'};
      case 'restaurant':
        return {'restaurant', 'restaurants', 'resturant', 'resturants', 'dining', 'food', 'مطعم', 'مطاعم'};
      case 'hotel':
        return {'hotel', 'hotels', 'resort', 'resorts', 'hostel', 'lodging', 'فندق', 'فنادق'};
      case 'outing':
        return {
          'outing', 'outings', 'outing places', 'outing place', 'park', 'parks',
          'garden', 'gardens', 'mall', 'malls', 'beach', 'beaches', 'cinema',
          'marina', 'marinas', 'promenade', 'promenades', 'corniche', 'corniches',
          'souk', 'souks', 'market', 'markets', 'bazaar', 'bazaars',
          'entertainment', 'nightlife', 'places', 'place',
          'خروجات', 'فسح',
        };
      default:
        return {category};
    }
  }

  Set<String> _categoryWords(String category) {
    switch (category) {
      case 'hotel':
        return {'hotel', 'hotels', 'hostel', 'resort', 'فندق', 'فنادق', 'اوتيل', 'أوتيل'};
      case 'restaurant':
        return {'restaurant', 'restaurants', 'resturant', 'resturants', 'restraunt', 'restraunts', 'مطعم', 'مطاعم', 'food', 'eat', 'اكل', 'أكل'};
      case 'cafe':
        return {'cafe', 'cafes', 'coffee', 'cafeteria', 'كافيه', 'كافيهات', 'كافتريا', 'كافيتريا', 'قهوة', 'مقهى'};
      case 'outing':
        return {
          'outing', 'outings', 'outing places', 'place', 'places', 'park', 'parks',
          'garden', 'gardens', 'mall', 'malls', 'cinema', 'beach', 'beaches', 'coast',
          'marina', 'marinas', 'promenade', 'corniche', 'souk', 'souks', 'market',
          'markets', 'bazaar', 'bazaars', 'entertainment', 'nightlife',
          'فسح', 'فسحة', 'خروجات', 'خروجة', 'حديقة', 'حدائق', 'مول', 'سينما', 'ساحل', 'شاطئ',
        };
      case 'tourist':
        return {
          'tourist', 'tourists', 'tourism', 'attraction', 'attractions', 'landmark',
          'landmarks', 'museum', 'museums', 'historic', 'historical',
          'archaeological', 'site', 'sites', 'monument', 'temple', 'citadel',
          'palace', 'mosque', 'church', 'مزار', 'مزارات', 'سياحي', 'سياحية',
          'معلم', 'معالم', 'متحف', 'متاحف', 'اثري', 'أثري'
        };
      default:
        return {category};
    }
  }

  String? _resolveCity(String text, String? selectedCityName) {
    final selected = selectedCityName?.trim();
    if (selected != null && selected.isNotEmpty) {
      final exact = _canonicalCityName(selected);
      if (exact != null) return exact;
    }

    final lower = _normalizeSearchText(text);
    if (lower.isEmpty) return null;

    final direct = _canonicalCityName(lower);
    if (direct != null) return direct;

    for (final entry in _cityNameMap.entries) {
      final key = _normalizeSearchText(entry.key);
      if (lower == key || lower.contains(key)) return entry.value;
    }

    return _inferCityFromKnownPlace(lower);
  }

  bool _isGlobalCitySelection(String? value) {
    final text = _normalizeSearchText(value ?? '');
    if (text.isEmpty) return true;
    return text == 'all egypt' ||
        text == 'egypt' ||
        text == 'all' ||
        text == 'كل مصر' ||
        text == 'مصر كلها';
  }

  String? _canonicalCityName(String text) {
    final normalized = _normalizeSearchText(text);
    if (normalized.isEmpty) return null;
    for (final entry in _cityNameMap.entries) {
      if (normalized == _normalizeSearchText(entry.key)) return entry.value;
    }
    for (final name in _cityCoordinates.keys) {
      if (normalized == _normalizeSearchText(name)) return name;
    }
    return null;
  }

  String _canonicalizeGeneratedCity(
    String rawCity, {
    String? query,
  }) {
    final raw = rawCity.trim();
    final queryText = _normalizeSearchText(query ?? '');

    // Do not force a hardcoded city from the place name.
    // The generated place must keep the provider's real city/locality unless
    // the user explicitly typed a city in the query. This keeps search generic
    // for any place in the five supported categories.

    if (raw.isNotEmpty) {
      final exactRaw = _canonicalCityName(raw);
      if (exactRaw != null) return exactRaw;

      final rawNorm = _normalizeSearchText(raw);
      for (final entry in _cityNameMap.entries) {
        final alias = _normalizeSearchText(entry.key);
        if (rawNorm == alias || rawNorm.contains(alias)) return entry.value;
      }

      return raw;
    }

    for (final entry in _cityNameMap.entries) {
      final alias = _normalizeSearchText(entry.key);
      if (queryText == alias || queryText.contains(alias)) return entry.value;
    }

    return '';
  }

  String? _inferCityFromKnownPlace(String text) {
    final lower = _normalizeSearchText(text);
    for (final entry in _canonicalCityMap.entries) {
      final key = _normalizeSearchText(entry.key);
      if (lower.contains(key) || key.contains(lower)) return entry.value;
    }
    return null;
  }

  String? _expectedCityForPlaceQuery(String query) {
    final q = _normalizeSearchText(query);
    if (q.isEmpty) return null;

    final fromIntent = PlaceSearchPipeline.extractCityIntentFromQuery(query);
    if (fromIntent != null && fromIntent.trim().isNotEmpty) {
      return fromIntent.trim();
    }

    // General rule:
    // Do NOT infer a city from a hardcoded place-name map.
    // Only force expected city when the user explicitly wrote it.
    // Examples:
    //   "Valley of the Kings"           -> no forced city
    //   "Valley of the Kings in Luxor"  -> expected Luxor
    //   "cafes in Sinai"                -> expected Sinai/location handling
    final explicitLocationMatch = RegExp(
      r'\b(?:in|near|around|at)\s+(.+)$',
    ).firstMatch(q);

    if (explicitLocationMatch == null) return null;

    final locationText = explicitLocationMatch.group(1)?.trim() ?? '';
    if (locationText.isEmpty) return null;

    final direct = _canonicalCityName(locationText);
    if (direct != null) return direct;

    for (final entry in _cityNameMap.entries) {
      final alias = _normalizeSearchText(entry.key);
      if (locationText == alias || locationText.contains(alias)) {
        return entry.value;
      }
    }

    // If it is a region/location not in the city map, return it as-is.
    // _cityMatchesExpected handles known regions like Sinai/North Coast.
    return locationText;
  }

  bool _cityMatchesExpected(String actualCity, String? expectedCity) {
    if ((expectedCity ?? '').trim().isEmpty) return true;

    final actual = _normalizeSearchText(actualCity);
    final expected = _normalizeSearchText(expectedCity!);
    if (actual == expected) return true;

    // If the provider returned a known major Egyptian city, it must match.
    // If it returned a locality/district/island/village that is not in our city map,
    // allow it because canonicalizeGeneratedCity will save the landmark under
    // the expected city inferred from the actual place name.
    final actualCanonical = _canonicalCityName(actualCity);
    if (actualCanonical != null) {
      return _normalizeSearchText(actualCanonical) == expected;
    }

    return true;
  }

  String _expectedSubtypeForPlaceText(String value, String? category) {
    final text = _normalizeSearchText('$value ${category ?? ''}');
    if (text.contains('tower')) return 'tower';
    if (text.contains('temple')) return 'temple';
    if (text.contains('palace')) return 'palace';
    if (text.contains('citadel') || text.contains('fort')) return 'citadel';
    if (text.contains('museum')) return 'museum';
    if (text.contains('library') || text.contains('bibliotheca')) return 'library';
    if (text.contains('sphinx')) return 'sphinx';
    if (text.contains('pyramid')) return 'pyramid';
    if (text.contains('mosque')) return 'mosque';
    if (text.contains('church')) return 'church';
    if (text.contains('cafe') || text.contains('coffee')) return 'cafe';
    if (text.contains('restaurant') || text.contains('dining')) return 'restaurant';
    if (text.contains('hotel') || text.contains('resort')) return 'hotel';
    return '';
  }

  bool _subtypeMatchesExpected({
    required String query,
    required String name,
    required String displayName,
    required String osmClass,
    required String osmType,
    String? category,
  }) {
    final expected = _expectedSubtypeForPlaceText(query, category);
    if (expected.isEmpty) return true;
    final text = _normalizeSearchText('$name $displayName $osmClass $osmType');
    switch (expected) {
      case 'tower':
        return text.contains('tower');
      case 'temple':
        return text.contains('temple');
      case 'palace':
        return text.contains('palace');
      case 'citadel':
        return RegExp(r'\b(citadel|fort|fortress|castle)\b').hasMatch(text);
      case 'museum':
        return text.contains('museum');
      case 'library':
        return text.contains('library') || text.contains('bibliotheca');
      case 'sphinx':
        return text.contains('sphinx');
      case 'pyramid':
        return text.contains('pyramid');
      case 'mosque':
        return text.contains('mosque');
      case 'church':
        return text.contains('church') || text.contains('cathedral');
      case 'cafe':
        return text.contains('cafe') || text.contains('coffee');
      case 'restaurant':
        return text.contains('restaurant') || text.contains('dining') || text.contains('food');
      case 'hotel':
        return text.contains('hotel') || text.contains('resort');
    }
    return true;
  }

  Future<({double lat, double lng})?> _resolveCityCoordinates(String city) async {
    final canonical = _canonicalCityName(city) ?? city.trim();
    return _cityCoordinates[canonical];
  }

  String? _cityFromOsmAddress(Map<String, dynamic> address) {
    final candidates = [
      address['city'],
      address['town'],
      address['village'],
      address['municipality'],
      address['county'],
      address['state'],
      address['governorate'],
    ];

    for (final c in candidates) {
      final text = (c ?? '').toString().trim();
      if (text.isEmpty) continue;
      final resolved = _canonicalizeGeneratedCity(text);
      if (resolved.toLowerCase() != 'egypt') return resolved;
    }
    return null;
  }


  List<Landmark> _withEnglishDisplayNames(List<Landmark> list) {
    final mapped = list.map((lm) {
      final english = _englishNameForLandmark(lm);
      if (english == null || english.trim().isEmpty) return lm;
      if (lm.name.trim() == english.trim()) return lm;
      return lm.copyWith(name: english.trim());
    }).toList();

    // Important: after changing Arabic/local names to English display names,
    // remove duplicate cards that represent the same real place.
    return _dedupeEquivalentLandmarks(mapped);
  }


  String? _canonicalEnglishNameFromText(String value) {
    final text = _normalizeSearchText(value);
    if (text.isEmpty) return null;

    const aliases = {
      'قهوة ريش': 'Cafe Riche',
      'كافيه ريش': 'Cafe Riche',
      'مقهى ريش': 'Cafe Riche',
      'cafe riche': 'Cafe Riche',
      'ريش': 'Cafe Riche',
      'قهوة الفيشاوي': 'El Fishawy Cafe',
      'كافيه الفيشاوي': 'El Fishawy Cafe',
      'مقهى الفيشاوي': 'El Fishawy Cafe',
      'الفيشاوي': 'El Fishawy Cafe',
      'fishawy': 'El Fishawy Cafe',
      'el fishawy': 'El Fishawy Cafe',
      'نجيب محفوظ كافيه': 'Naguib Mahfouz Cafe',
      'كافيه نجيب محفوظ': 'Naguib Mahfouz Cafe',
      'naguib mahfouz cafe': 'Naguib Mahfouz Cafe',
      'جروبي': 'Groppi Cafe',
      'groppi': 'Groppi Cafe',
      'مطعم صبحي كابر': 'Sobhy Kaber Restaurant',
      'صبحي كابر': 'Sobhy Kaber Restaurant',
      'sobhy kaber': 'Sobhy Kaber Restaurant',
      'كشري التحرير': 'Koshary El Tahrir',
      'koshary el tahrir': 'Koshary El Tahrir',
      'خان الخليلي': 'Khan el-Khalili',
      'خان الخليل': 'Khan el-Khalili',
      'khan el khalili': 'Khan el-Khalili',
      'khan el-khalili': 'Khan el-Khalili',
      'المتحف المصري الكبير': 'Grand Egyptian Museum',
      'متحف المصري الكبير': 'Grand Egyptian Museum',
      'grand egyptian museum': 'Grand Egyptian Museum',
      'المتحف المصري': 'Egyptian Museum',
      'egyptian museum': 'Egyptian Museum',
      'برج القاهرة': 'Cairo Tower',
      'برج القاهره': 'Cairo Tower',
      'cairo tower': 'Cairo Tower',
      'قلعه صلاح الدين': 'Citadel of Cairo',
      'قلعة صلاح الدين': 'Citadel of Cairo',
      'قلعة الجبل': 'Citadel of Cairo',
      'قلعه الجبل': 'Citadel of Cairo',
      'cairo citadel': 'Citadel of Cairo',
      'citadel of cairo': 'Citadel of Cairo',
      'saladin citadel': 'Citadel of Cairo',
      'saladin citadel of cairo': 'Citadel of Cairo',
      'قصر عابدين': 'Abdeen Palace',
      'abdeen palace': 'Abdeen Palace',
      'قصر المنتزه': 'Montaza Palace',
      'montaza palace': 'Montaza Palace',
      'montazah palace': 'Montaza Palace',
      'مكتبة الإسكندرية': 'Bibliotheca Alexandrina',
      'مكتبه الاسكندريه': 'Bibliotheca Alexandrina',
      'bibliotheca alexandrina': 'Bibliotheca Alexandrina',
      'alexandria library': 'Bibliotheca Alexandrina',
      'معبد الأقصر': 'Luxor Temple',
      'معبد الاقصر': 'Luxor Temple',
      'luxor temple': 'Luxor Temple',
      'معبد الكرنك': 'Karnak Temple',
      'karnak temple': 'Karnak Temple',
      'وادي الملوك': 'Valley of the Kings',
      'valley of the kings': 'Valley of the Kings',
      'معبد حتشبسوت': 'Temple of Hatshepsut',
      'hatshepsut temple': 'Temple of Hatshepsut',
      'temple of hatshepsut': 'Temple of Hatshepsut',
      'معبد فيلة': 'Philae Temple',
      'معبد فيله': 'Philae Temple',
      'philae temple': 'Philae Temple',
      'أبو سمبل': 'Abu Simbel Temples',
      'ابو سمبل': 'Abu Simbel Temples',
      'abu simbel': 'Abu Simbel Temples',
      'أهرامات الجيزة': 'Pyramids of Giza',
      'اهرامات الجيزه': 'Pyramids of Giza',
      'pyramids of giza': 'Pyramids of Giza',
      'giza pyramids': 'Pyramids of Giza',
      'great pyramid': 'Pyramids of Giza',
      'great pyramid of giza': 'Pyramids of Giza',
      'أبو الهول': 'Great Sphinx of Giza',
      'ابو الهول': 'Great Sphinx of Giza',
      'great sphinx of giza': 'Great Sphinx of Giza',
      'واحة سيوة': 'Siwa Oasis',
      'واحه سيوه': 'Siwa Oasis',
      'siwa oasis': 'Siwa Oasis',
    };

    for (final entry in aliases.entries) {
      final key = _normalizeSearchText(entry.key);
      if (text == key || text.contains(key)) return entry.value;
    }
    return null;
  }

  String? _englishNameForLandmark(Landmark lm) {
    final rawText = '${lm.name} ${lm.description} ${lm.shortDescription} ${lm.address} ${lm.wikipediaUrl ?? ''}';
    final canonical = _canonicalEnglishNameFromText(rawText);
    if (canonical != null) return canonical;

    final text = _normalizeSearchText(rawText);

    const aliases = {
      'قهوة ريش': 'Cafe Riche',
      'كافيه ريش': 'Cafe Riche',
      'مقهى ريش': 'Cafe Riche',
      'cafe riche': 'Cafe Riche',
      'ريش': 'Cafe Riche',
      'قهوة الفيشاوي': 'El Fishawy Cafe',
      'كافيه الفيشاوي': 'El Fishawy Cafe',
      'مقهى الفيشاوي': 'El Fishawy Cafe',
      'الفيشاوي': 'El Fishawy Cafe',
      'fishawy': 'El Fishawy Cafe',
      'el fishawy': 'El Fishawy Cafe',
      'نجيب محفوظ كافيه': 'Naguib Mahfouz Cafe',
      'كافيه نجيب محفوظ': 'Naguib Mahfouz Cafe',
      'naguib mahfouz cafe': 'Naguib Mahfouz Cafe',
      'جروبي': 'Groppi Cafe',
      'groppi': 'Groppi Cafe',
      'مطعم صبحي كابر': 'Sobhy Kaber Restaurant',
      'صبحي كابر': 'Sobhy Kaber Restaurant',
      'sobhy kaber': 'Sobhy Kaber Restaurant',
      'كشري التحرير': 'Koshary El Tahrir',
      'koshary el tahrir': 'Koshary El Tahrir',
      'المتحف المصري الكبير': 'Grand Egyptian Museum',
      'متحف المصري الكبير': 'Grand Egyptian Museum',
      'grand egyptian museum': 'Grand Egyptian Museum',
      'المتحف المصري': 'Egyptian Museum',
      'egyptian museum': 'Egyptian Museum',
      'خان الخليلي': 'Khan el-Khalili',
      'خان الخليل': 'Khan el-Khalili',
      'khan el khalili': 'Khan el-Khalili',
      'khan el-khalili': 'Khan el-Khalili',
      'برج القاهره': 'Cairo Tower',
      'برج القاهرة': 'Cairo Tower',
      'cairo tower': 'Cairo Tower',
      'قلعه صلاح الدين': 'Citadel of Cairo',
      'قلعة صلاح الدين': 'Citadel of Cairo',
      'citadel of cairo': 'Citadel of Cairo',
      'قلعه قايتباي': 'Citadel of Qaitbay',
      'قلعة قايتباي': 'Citadel of Qaitbay',
      'citadel of qaitbay': 'Citadel of Qaitbay',
      'qaitbay citadel': 'Citadel of Qaitbay',
      'قصر عابدين': 'Abdeen Palace',
      'abdeen palace': 'Abdeen Palace',
      'قصر المنتزه': 'Montaza Palace',
      'montaza palace': 'Montaza Palace',
      'montazah palace': 'Montaza Palace',
      'مكتبه الاسكندريه': 'Bibliotheca Alexandrina',
      'مكتبة الإسكندرية': 'Bibliotheca Alexandrina',
      'bibliotheca alexandrina': 'Bibliotheca Alexandrina',
      'alexandria library': 'Bibliotheca Alexandrina',
      'معبد الاقصر': 'Luxor Temple',
      'معبد الأقصر': 'Luxor Temple',
      'luxor temple': 'Luxor Temple',
      'معبد الكرنك': 'Karnak Temple',
      'karnak temple': 'Karnak Temple',
      'وادي الملوك': 'Valley of the Kings',
      'valley of the kings': 'Valley of the Kings',
      'معبد حتشبسوت': 'Temple of Hatshepsut',
      'hatshepsut temple': 'Temple of Hatshepsut',
      'temple of hatshepsut': 'Temple of Hatshepsut',
      'معبد فيله': 'Philae Temple',
      'philae temple': 'Philae Temple',
      'ابو سمبل': 'Abu Simbel Temples',
      'أبو سمبل': 'Abu Simbel Temples',
      'abu simbel': 'Abu Simbel Temples',
      'اهرامات الجيزه': 'Pyramids of Giza',
      'أهرامات الجيزة': 'Pyramids of Giza',
      'pyramids of giza': 'Pyramids of Giza',
      'giza pyramids': 'Pyramids of Giza',
      'great pyramid': 'Pyramids of Giza',
      'great pyramid of giza': 'Pyramids of Giza',
      'ابو الهول': 'Great Sphinx of Giza',
      'أبو الهول': 'Great Sphinx of Giza',
      'great sphinx of giza': 'Great Sphinx of Giza',
      'siwa oasis': 'Siwa Oasis',
      'واحه سيوه': 'Siwa Oasis',
      'واحة سيوة': 'Siwa Oasis',
    };

    for (final entry in aliases.entries) {
      final key = _normalizeSearchText(entry.key);
      if (text == key || text.contains(key)) return entry.value;
    }

    // If the stored name is already Latin, keep it as-is.
    if (_hasLatinLetters(lm.name)) return lm.name.trim();

    // Last safe fallback: show Arabic/local names as readable Latin text in cards
    // so image/details pipelines do not receive Arabic display names.
    if (_hasArabicLetters(lm.name)) {
      final romanized = _romanizeArabicName(lm.name);
      if (romanized.trim().isNotEmpty && _hasLatinLetters(romanized)) {
        return romanized.trim();
      }
    }

    return null;
  }


  String _romanizeArabicName(String input) {
    var value = input.trim();
    if (value.isEmpty) return value;

    const phraseAliases = {
      'قهوة': 'Cafe',
      'كافيه': 'Cafe',
      'مقهى': 'Cafe',
      'مطعم': 'Restaurant',
      'فندق': 'Hotel',
      'قصر': 'Palace',
      'متحف': 'Museum',
      'معبد': 'Temple',
      'قلعة': 'Citadel',
      'برج': 'Tower',
      'حديقة': 'Garden',
      'شاطئ': 'Beach',
      'سوق': 'Market',
      'خان': 'Khan',
    };

    for (final entry in phraseAliases.entries) {
      value = value.replaceAll(entry.key, entry.value);
    }

    const chars = {
      'ا': 'a', 'أ': 'a', 'إ': 'e', 'آ': 'a', 'ب': 'b', 'ت': 't',
      'ث': 'th', 'ج': 'g', 'ح': 'h', 'خ': 'kh', 'د': 'd', 'ذ': 'z',
      'ر': 'r', 'ز': 'z', 'س': 's', 'ش': 'sh', 'ص': 's', 'ض': 'd',
      'ط': 't', 'ظ': 'z', 'ع': 'a', 'غ': 'gh', 'ف': 'f', 'ق': 'q',
      'ك': 'k', 'ل': 'l', 'م': 'm', 'ن': 'n', 'ه': 'h', 'ة': 'a',
      'و': 'w', 'ؤ': 'w', 'ي': 'y', 'ى': 'a', 'ئ': 'y', 'ء': '',
      'َ': '', 'ً': '', 'ُ': '', 'ٌ': '', 'ِ': '', 'ٍ': '', 'ْ': '', 'ّ': '',
    };

    final out = StringBuffer();
    for (final rune in value.runes) {
      final ch = String.fromCharCode(rune);
      out.write(chars[ch] ?? ch);
    }

    return out
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .split(' ')
        .where((w) => w.trim().isNotEmpty)
        .map((w) {
          final t = w.trim();
          if (t.isEmpty) return t;
          if (RegExp(r'^[A-Z][a-zA-Z]*$').hasMatch(t)) return t;
          return t[0].toUpperCase() + (t.length > 1 ? t.substring(1) : '');
        })
        .join(' ')
        .trim();
  }

  bool _hasLatinLetters(String text) {
    return RegExp(r'[a-zA-Z]').hasMatch(text);
  }

  bool _hasArabicLetters(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }

  String _cleanNameCandidate(String value) {
    var v = value.trim();
    if (v.contains(',')) {
      v = v.split(',').first.trim();
    }
    v = v.replaceAll(RegExp(r'\s+'), ' ').replaceAll('،', '').trim();
    return v;
  }

  String _nameFromOsmNamedetails(Map<String, dynamic> item) {
    final namedetails = item['namedetails'];

    if (namedetails is Map) {
      final en = (namedetails['name:en'] ??
              namedetails['name:latin'] ??
              namedetails['official_name:en'] ??
              '')
          .toString()
          .trim();
      if (en.isNotEmpty) return _cleanNameCandidate(en);

      final localName = (namedetails['name'] ?? '').toString().trim();
      if (localName.isNotEmpty) return _cleanNameCandidate(localName);
    }

    final directName = (item['name'] ?? '').toString().trim();
    if (directName.isNotEmpty) return _cleanNameCandidate(directName);

    final displayName = (item['display_name'] ?? '').toString().trim();
    if (displayName.isNotEmpty) return _cleanNameCandidate(displayName);

    return '';
  }

  String _chooseGeneratedName({
    required String rawQuery,
    required Map<String, dynamic> osmItem,
  }) {
    final query = _cleanNameCandidate(rawQuery);
    final osmName = _nameFromOsmNamedetails(osmItem);
    final fallback = (osmItem['display_name'] ?? '').toString();

    final canonical = _canonicalEnglishNameFromText('$query $osmName $fallback');
    if (canonical != null) return canonical;

    // If user typed English but OSM returned Arabic/local only,
    // keep the English query to protect image search quality.
    if (_hasLatinLetters(query) && !_hasLatinLetters(osmName)) {
      return query;
    }

    // Prefer English/Latin names whenever OSM provides one,
    // even if the user searched in Arabic.
    if (osmName.isNotEmpty && _hasLatinLetters(osmName)) return osmName;

    // If OSM only returns Arabic/local text, keep the app card English-ish
    // by using a deterministic romanized fallback instead of storing Arabic.
    if (osmName.isNotEmpty && _hasArabicLetters(osmName)) {
      final romanized = _romanizeArabicName(osmName);
      if (romanized.trim().isNotEmpty && _hasLatinLetters(romanized)) {
        return romanized.trim();
      }
    }

    if (query.isNotEmpty && _hasArabicLetters(query)) {
      final romanized = _romanizeArabicName(query);
      if (romanized.trim().isNotEmpty && _hasLatinLetters(romanized)) {
        return romanized.trim();
      }
    }

    if (osmName.isNotEmpty) return osmName;

    if (fallback.trim().isNotEmpty) {
      final cleaned = _cleanOsmDisplayName(fallback, rawQuery);
      if (cleaned.trim().isNotEmpty) return cleaned;
    }

    return query;
  }

  String _cleanOsmDisplayName(String displayName, String rawQuery) {
    final parts = displayName
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return rawQuery.trim();

    final q = _normalizeSearchText(rawQuery);
    parts.sort((a, b) =>
        _looseNameScore(b, q).compareTo(_looseNameScore(a, q)));

    final best = parts.first;
    if (_looseNameScore(best, rawQuery) >= 0.35) return best;
    return parts.first;
  }

  bool _isEgyptianResult({
    required String title,
    required String description,
    required String cityName,
    required String query,
  }) {
    final text = _normalizeSearchText('$title $description $cityName $query');
    if (text.contains('egypt') || text.contains('مصر')) return true;
    if (_resolveCity(text, null) != null) return true;
    if (_inferCityFromKnownPlace(text) != null) return true;
    return false;
  }

  bool _isLooseNameMatch(String name, String query) {
    return _looseNameScore(name, query) >= 0.45;
  }

  List<Landmark> _dedupeEquivalentLandmarks(List<Landmark> list) {
    final result = <Landmark>[];
    final seen = <String>{};

    for (final lm in list) {
      final key = _equivalenceKey(lm);
      if (seen.add(key)) {
        result.add(lm);
      }
    }

    return result;
  }

  String _canonicalPlaceNameForKey(String rawName) {
    final name = _normalizeSearchText(rawName);

    // Pyramid-related queries and generated docs often point to the same
    // user-facing place/details in this app. Keep them as one card.
    const pyramidAliases = {
      'pyramid',
      'pyramids',
      'pyramids of giza',
      'giza pyramids',
      'great pyramid',
      'great pyramid of giza',
      'khufu pyramid',
      'pyramid of khufu',
      'اهرامات الجيزه',
      'اهرامات الجيزة',
      'اهرام الجيزه',
      'اهرام الجيزة',
    };
    if (pyramidAliases.any((a) {
      final k = _normalizeSearchText(a);
      return name == k || name.contains(k) || k.contains(name);
    })) {
      return 'pyramids_of_giza';
    }


    const citadelCairoAliases = {
      'citadel of cairo',
      'cairo citadel',
      'saladin citadel',
      'saladin citadel of cairo',
      'قلعه صلاح الدين',
      'قلعة صلاح الدين',
      'قلعه الجبل',
      'قلعة الجبل',
    };
    if (citadelCairoAliases.any((a) {
      final k = _normalizeSearchText(a);
      return name == k || name.contains(k) || k.contains(name);
    })) {
      return 'citadel_of_cairo';
    }

    const abdeenAliases = {
      'abdeen palace',
      'قصر عابدين',
    };
    if (abdeenAliases.any((a) {
      final k = _normalizeSearchText(a);
      return name == k || name.contains(k) || k.contains(name);
    })) {
      return 'abdeen_palace';
    }

    const khanAliases = {
      'khan el khalili',
      'khan el-khalili',
      'khan al khalili',
      'khan al-khalili',
      'خان الخليلي',
      'خان الخليل',
    };
    if (khanAliases.any((a) {
      final k = _normalizeSearchText(a);
      return name == k || name.contains(k) || k.contains(name);
    })) {
      return 'khan_el_khalili';
    }

    const gemAliases = {
      'grand egyptian museum',
      'المتحف المصري الكبير',
      'متحف المصري الكبير',
    };
    if (gemAliases.any((a) {
      final k = _normalizeSearchText(a);
      return name == k || name.contains(k) || k.contains(name);
    })) {
      return 'grand_egyptian_museum';
    }

    const egyptianMuseumAliases = {
      'egyptian museum',
      'المتحف المصري',
    };
    if (egyptianMuseumAliases.any((a) {
      final k = _normalizeSearchText(a);
      return name == k || name.contains(k) || k.contains(name);
    })) {
      return 'egyptian_museum';
    }

    return name;
  }

  bool _containsEquivalent(List<Landmark> list, Landmark target) {
    final key = _equivalenceKey(target);
    return list.any((lm) => _equivalenceKey(lm) == key);
  }

  String _equivalenceKey(Landmark lm) {
    final displayName = _englishNameForLandmark(lm) ?? lm.name;
    final name = _canonicalPlaceNameForKey(displayName);
    final city = _normalizeSearchText(lm.city);

    if (name.isEmpty) {
      return '${lm.lat.toStringAsFixed(4)}|${lm.lng.toStringAsFixed(4)}';
    }

    // If coordinates are present and the canonical name is the same, this
    // prevents duplicate cards even when old Firebase docs have different IDs.
    return '$name|$city';
  }

  String _normalizeSearchText(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[إأآا]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _looseNameScore(String a, String b) {
    final x = _normalizeSearchText(a);
    final y = _normalizeSearchText(b);
    if (x.isEmpty || y.isEmpty) return 0;
    if (x == y) return 1;
    if (x.contains(y) || y.contains(x)) {
      final minLen = math.min(x.length, y.length);
      final maxLen = math.max(x.length, y.length);
      return 0.72 + (0.28 * minLen / maxLen);
    }

    final xt = _importantTokens(x);
    final yt = _importantTokens(y);
    if (xt.isEmpty || yt.isEmpty) return 0;
    final inter = xt.intersection(yt).length;
    final union = xt.union(yt).length;
    final tokenScore = union == 0 ? 0.0 : inter / union;

    final editScore = _similarityByLevenshtein(x, y);
    return math.max(tokenScore, editScore * 0.92);
  }

  double _similarityByLevenshtein(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;
    final distance = _levenshtein(a, b);
    final maxLen = math.max(a.length, b.length);
    return 1 - (distance / maxLen);
  }

  int _levenshtein(String s, String t) {
    final m = s.length;
    final n = t.length;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));

    for (var i = 0; i <= m; i++) dp[i][0] = i;
    for (var j = 0; j <= n; j++) dp[0][j] = j;

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = s.codeUnitAt(i - 1) == t.codeUnitAt(j - 1) ? 0 : 1;
        dp[i][j] = math.min(
          math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1),
          dp[i - 1][j - 1] + cost,
        );
      }
    }
    return dp[m][n];
  }
}
