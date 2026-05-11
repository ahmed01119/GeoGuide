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

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'package:geoguide/core/place_category_normalizer.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/services/Wikipedia%20service.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/services/landmark_cache.dart';
import 'package:geoguide/services/nearby-service.dart';

class SearchResult {
  final String correctedQuery;
  final List<Landmark> results;
  final List<String> suggestions;
  final String? detectedCity;
  final String? detectedCategory;

  const SearchResult({
    required this.correctedQuery,
    required this.results,
    this.suggestions = const [],
    this.detectedCity,
    this.detectedCategory,
  });

  static const empty = SearchResult(correctedQuery: '', results: []);
}

class SearchEngine {
  SearchEngine({
    FirebaseService? firebase,
    WikipediaService? wikipedia,
    NearbyService? nearby,
  })  : _firebase = firebase ?? FirebaseService(),
        _wikipedia = wikipedia ?? WikipediaService(),
        _nearby = nearby ?? NearbyService(),
        _cache = LandmarkCache.instance;

  final FirebaseService _firebase;
  final WikipediaService _wikipedia;
  final NearbyService _nearby;
  final LandmarkCache _cache;

  List<Landmark>? _index;
  DateTime? _indexTimestamp;
  static const Duration _indexTtl = Duration(minutes: 10);

  String _lastHintKey = '';
  List<String> _lastHints = [];

  // Prevent repeated background saves for the same category/city batch.
  final Set<String> _backgroundSaveKeys = {};

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
    'matrouh': 'Siwa',
    'marsa matrouh': 'Siwa',
    'matrouh governorate': 'Siwa',
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
      print('[SearchEngine] rejected unsupported query outside app categories: $trimmed');
      return SearchResult(
        correctedQuery: trimmed,
        results: const [],
        suggestions: const [],
      );
    }

    final index = await _getIndex();
    final corrected = _resolveCorrectedQuery(trimmed, index);
    final resolvedCityFromQuery = _resolveCity('$trimmed $corrected', null);
    final detectedCategory = _detectCategory('$trimmed $corrected');

    // City can come either from the query itself or from the dropdown.
    // IMPORTANT: the city typed in the query must win over the dropdown.
    // Example: dropdown = "All Egypt" and query = "cafes in cairo"
    // should search Cairo, not All Egypt. This was the reason category searches
    // were returning very few/no results.
    final selectedCityName = _isGlobalCitySelection(cityName) ? null : cityName?.trim();
    final effectiveCategoryCity = (resolvedCityFromQuery ?? '').trim().isNotEmpty
        ? resolvedCityFromQuery
        : selectedCityName;

    final isCategoryQuery = detectedCategory != null &&
        _isGenericCategoryQuery(
          trimmed,
          detectedCategory,
          effectiveCategoryCity,
        );

    // IMPORTANT:
    // Selected/typed city filters only category searches (cafes/restaurants/hotels).
    // For place-name searches, search across Egypt so a place in another city can be found.
    final shouldUseCityFilter = isCategoryQuery &&
        (effectiveCategoryCity ?? '').trim().isNotEmpty;

    // Category searches need more than the normal single-place result limit.
    // Example: "cafes in cairo" should return a useful list, not 3-4 items.
    final effectiveMaxResults = isCategoryQuery ? math.max(maxResults, 30) : maxResults;

    final filtered = _applyFilters(
      index,
      cityId: shouldUseCityFilter && (cityId ?? '').trim().isNotEmpty ? cityId : null,
      cityName: shouldUseCityFilter ? effectiveCategoryCity : null,
      category: isCategoryQuery ? detectedCategory : null,
    );

    final ranked = _rank(
      query: corrected,
      rawQuery: trimmed,
      landmarks: filtered,
      cityHint: shouldUseCityFilter ? effectiveCategoryCity : resolvedCityFromQuery,
      categoryHint: isCategoryQuery ? detectedCategory : null,
    );

    var results = ranked.take(effectiveMaxResults).toList();

    // For generic category searches like "tourists in cairo", the user expects
    // all already-saved matching places from Firebase, not only items whose name
    // text matches the literal word "tourists". This also makes previously
    // searched/generated places appear immediately on the next search.
    if (isCategoryQuery && detectedCategory != null) {
      final savedCategoryResults = _savedCategoryResultsForQuery(
        index,
        category: detectedCategory,
        cityName: effectiveCategoryCity,
        cityId: cityId,
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

        print('[SearchEngine] category Nominatim results=${providerResults[0].length}, Overpass results=${providerResults[1].length} for "$trimmed"');

        final generated = _mergeSearchResults(
          providerResults[0],
          providerResults[1],
          trimmed,
        );

        if (generated.isNotEmpty) {
          results = _mergeSearchResults(generated, results, trimmed)
              .take(effectiveMaxResults)
              .toList();

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
      }
    }

    final strongFirst = results.isNotEmpty && _isStrongMatch(results.first, trimmed);

    if (!isCategoryQuery && !strongFirst) {
      final generated = await _generateSinglePlaceFromProviders(
        query: corrected,
        rawQuery: trimmed,
        category: detectedCategory,
        selectedCityName: cityName,
        existingResults: results,
      );

      if (generated != null && !_containsEquivalent(results, generated)) {
        final saved = await _safePersistAndReturn(generated);
        final finalPlace = saved ?? generated;
        results = _mergeSearchResults([finalPlace], results, trimmed)
            .take(maxResults)
            .toList();
        _clearIndex();
      }
    }

    results = _prioritizeExactQuery(results, trimmed).take(effectiveMaxResults).toList();

    // UI display rule:
    // Search result cards should use English names whenever we can resolve one,
    // even if the stored Firebase document has an Arabic/local name.
    // This keeps image search, hero tags, and card rendering stable.
    results = _withEnglishDisplayNames(results);

    final suggestions = await getHints(trimmed, cityName: cityName);

    final detectedCityForResponse =
        _detectedCityFromResults(results, '$trimmed $corrected') ??
            resolvedCityFromQuery;

    return SearchResult(
      correctedQuery: corrected,
      results: results,
      suggestions: suggestions,
      detectedCity: detectedCityForResponse,
      detectedCategory: detectedCategory,
    );
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
      final lmCity = _normalizeSearchText(lm.city);

      var score = 0.0;

      score += _looseNameScore(lm.name, rawQuery) * 80;
      score += _looseNameScore(lm.name, query) * 60;

      if (name == raw || name == q) score += 120;
      if (name.contains(raw) || raw.contains(name)) score += 45;
      if (desc.contains(raw)) score += 12;

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
    final osm = await _fetchOsmTextSearchLandmark(
      query: query,
      rawQuery: rawQuery,
      category: category,
      cityName: selectedCityName,
      existingResults: existingResults,
    );
    if (osm != null) return osm;

    final wiki = await _fetchWikipediaLandmark(
      query: query,
      rawQuery: rawQuery,
      category: category,
      cityName: selectedCityName,
      existingResults: existingResults,
    );
    if (wiki != null) return wiki;

    return null;
  }

  Future<Landmark?> _fetchOsmTextSearchLandmark({
    required String query,
    required String rawQuery,
    String? category,
    String? cityName,
    required List<Landmark> existingResults,
  }) async {
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
        imageUrl: place.imageUrl.trim(),
        mediaUrls: place.imageUrl.trim().isNotEmpty ? [place.imageUrl.trim()] : const [],
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
        final saved = await _safePersistAndReturn(landmark);
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

        final res = await http.get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'GeoGuideApp/1.0 (student-graduation-project)',
          },
        ).timeout(const Duration(seconds: 8));

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

          final saved = await _safePersistAndReturn(landmark);
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
      return 'outing';
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

  Future<Landmark?> _safePersistAndReturn(Landmark landmark) async {
    try {
      if (landmark.name.trim().isEmpty) return null;
      if (landmark.city.trim().isEmpty || landmark.city.trim().toLowerCase() == 'egypt') {
        print('[SearchEngine] persist skipped: invalid city for ${landmark.name}');
        return null;
      }
      if (_isBlockedNonPlaceResult(
        name: landmark.name,
        displayName: '${landmark.description} ${landmark.address}',
        category: landmark.category,
      )) {
        print('[SearchEngine] persist skipped non-place: ${landmark.name}');
        return null;
      }

      final canonicalName = _canonicalEnglishNameFromText(
        '${landmark.name} ${landmark.description} ${landmark.shortDescription} ${landmark.address} ${landmark.wikipediaUrl ?? ''}',
      );
      final landmarkToSave = canonicalName == null
          ? landmark
          : landmark.copyWith(name: canonicalName);

      final id = await _firebase.saveLandmark(landmarkToSave);
      final saved = landmarkToSave.copyWith(id: id);
      _cache.merge(saved);
      return saved;
    } catch (e) {
      print('[SearchEngine] persist failed for ${landmark.name}: $e');
      return null;
    }
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

  bool _isGenericCategoryQuery(String query, String category, String? cityName) {
    final normalized = _normalizeSearchText(query);
    final city = _normalizeSearchText(cityName ?? '');
    final cityFromQuery = _normalizeSearchText(_resolveCity(query, null) ?? '');

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
      if (city.isNotEmpty) ...city.split(' '),
      if (cityFromQuery.isNotEmpty) ...cityFromQuery.split(' '),
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
        return {'outing', 'outings', 'park', 'parks', 'garden', 'gardens', 'mall', 'malls', 'beach', 'beaches', 'cinema', 'خروجات', 'فسح'};
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
        return {'outing', 'outings', 'park', 'parks', 'garden', 'mall', 'cinema', 'beach', 'coast', 'فسح', 'فسحة', 'خروجات', 'خروجة', 'حديقة', 'حدائق', 'مول', 'سينما', 'ساحل', 'شاطئ'};
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
