// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

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
  static const _indexTtl = Duration(minutes: 10);

  String _lastHintKey = '';
  List<String> _lastHints = [];

  static const Set<String> _providerGeneratedCategories = {
    'hotel',
    'restaurant',
    'cafe',
    'tourist',
    'outing',
  };

  static const Map<String, String> _canonicalCityMap = {
    'great pyramid of giza': 'Giza',
    'pyramids of giza': 'Giza',
    'giza pyramids': 'Giza',
    'great sphinx of giza': 'Giza',
    'egyptian museum': 'Cairo',
    'grand egyptian museum': 'Giza',
    'khan el-khalili': 'Cairo',
    'citadel of cairo': 'Cairo',
    'cairo tower': 'Cairo',
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
      'khufu pyramid',
      'pyramid of khufu',
    ],
    'great sphinx of giza': ['sphinx', 'giza sphinx'],
    'citadel of qaitbay': ['qaitbay', 'qaitbay citadel'],
    'karnak temple': ['karnak'],
    'luxor temple': ['luxor'],
    'philae temple': ['philae'],
    'abu simbel temples': ['abu simbel'],
    'bibliotheca alexandrina': ['alexandria library'],
    'temple of edfu': ['edfu temple', 'edfu'],
    'temple of kom ombo': ['kom ombo temple', 'kom ombo'],
    'montaza palace': ['montazah palace', 'montaza', 'montazah'],
  };

  static const List<String> _famousPlaces = [
    'Great Pyramid of Giza',
    'Great Sphinx of Giza',
    'Egyptian Museum',
    'Grand Egyptian Museum',
    'Cairo Tower',
    'Khan el-Khalili',
    'Citadel of Cairo',
    'Luxor Temple',
    'Karnak Temple',
    'Valley of the Kings',
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
    'giza': 'Giza',
    'الجيزة': 'Giza',
    'الجيزه': 'Giza',
    'جيزة': 'Giza',
    'جيزه': 'Giza',
    'giza egypt': 'Giza',
    'luxor': 'Luxor',
    'الأقصر': 'Luxor',
    'الاقصر': 'Luxor',
    'aswan': 'Aswan',
    'أسوان': 'Aswan',
    'اسوان': 'Aswan',
    'alexandria': 'Alexandria',
    'alex': 'Alexandria',
    'الإسكندرية': 'Alexandria',
    'الاسكندرية': 'Alexandria',
    'اسكندرية': 'Alexandria',
    'siwa': 'Siwa',
    'سيوة': 'Siwa',
    'dahab': 'Dahab',
    'دهب': 'Dahab',
    'sharm': 'Sharm El Sheikh',
    'sharm el sheikh': 'Sharm El Sheikh',
    'شرم': 'Sharm El Sheikh',
    'شرم الشيخ': 'Sharm El Sheikh',
    'hurghada': 'Hurghada',
    'الغردقة': 'Hurghada',
    'غردقة': 'Hurghada',
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

  Future<SearchResult> search({
    required String query,
    String? cityId,
    String? cityName,
    int maxResults = 10,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return SearchResult.empty;

    final index = await _getIndex();
    final corrected = _resolveCorrectedQuery(trimmed, index);
    final resolvedCity = _resolveCity('$trimmed $corrected', cityName);
    final detectedCategory = _detectCategory('$trimmed $corrected');

    final selectedCity = cityName?.trim().toLowerCase();
    final inferredCity = resolvedCity?.trim().toLowerCase();
    final hasCityConflict = selectedCity != null &&
        selectedCity.isNotEmpty &&
        inferredCity != null &&
        inferredCity.isNotEmpty &&
        inferredCity != selectedCity;

    final effectiveCityId = hasCityConflict ? null : cityId;

    final filtered = _applyFilters(
      index,
      cityId: effectiveCityId,
      cityName: resolvedCity,
      category: detectedCategory,
    );

    final ranked = _rank(
      query: corrected,
      rawQuery: trimmed,
      landmarks: filtered,
      cityHint: resolvedCity,
      categoryHint: detectedCategory,
    );

    var results = ranked.take(maxResults).toList();

    final isCategoryQuery = detectedCategory != null;
    final isGenericCategoryQuery = isCategoryQuery &&
        _isGenericCategoryQuery(
          trimmed,
          detectedCategory!,
          resolvedCity ?? cityName,
        );

    // Provider categories (hotel/restaurant/cafe/tourist/outing) should be generated
    // from Nearby/Overpass when local Firebase results are weak or missing.
    if (isCategoryQuery && _providerGeneratedCategories.contains(detectedCategory)) {
      final exactCategoryCount = results.where((lm) {
        final normalized =
            PlaceCategoryNormalizer.normalize(lm.category, contextText: lm.name);
        return normalized == detectedCategory;
      }).length;

      if (exactCategoryCount < 3 || results.isEmpty) {
        final generated = await _generateFromNearbyProvider(
          category: detectedCategory!,
          cityName: resolvedCity ?? cityName,
          rawQuery: trimmed,
          maxResults: maxResults,
          preferNameMatch: !isGenericCategoryQuery,
        );

        if (generated.isNotEmpty) {
          results = _dedupe([...generated, ...results])
              .where((lm) {
                final normalized = PlaceCategoryNormalizer.normalize(
                  lm.category,
                  contextText: lm.name,
                );
                return normalized == detectedCategory;
              })
              .take(maxResults)
              .toList();
          _index = null;
          _indexTimestamp = null;
        }
      }
    }

    var strongEnough = results.isNotEmpty &&
        _score(results.first, corrected, trimmed, resolvedCity,
                detectedCategory) >=
            40;

    // General smart place-name fallback. This avoids adding a manual alias for every place.
    // Examples: "Africa Park", "alex lib", "luxr temple".
    if (!isGenericCategoryQuery &&
        (!strongEnough ||
            results.isEmpty ||
            !_isStrongNameMatch(results.first, corrected, trimmed))) {
      final osm = await _fetchOsmTextSearchLandmark(
        query: corrected,
        rawQuery: trimmed,
        category: detectedCategory,
        cityName: resolvedCity ?? cityName,
        existingResults: results,
      );

      if (osm != null && !_containsEquivalent(results, osm)) {
        final savedOsm = await _safePersistAndReturn(osm);
        final displayOsm = savedOsm ??
            osm.copyWith(
              id: 'generated_${DateTime.now().microsecondsSinceEpoch}',
            );
        results = [displayOsm, ...results].take(maxResults).toList();
        strongEnough = true;
      }
    }

    // Wikipedia fallback remains available for tourist/general named places.
    if (!isGenericCategoryQuery &&
        (!strongEnough ||
            results.isEmpty ||
            !_isStrongNameMatch(results.first, corrected, trimmed))) {
      final wiki = await _fetchWikipediaLandmark(
        query: corrected,
        rawQuery: trimmed,
        cityName: resolvedCity ?? cityName,
        category: detectedCategory,
        existingResults: results,
      );

      if (wiki != null && !_containsEquivalent(results, wiki)) {
        final savedWiki = await _safePersistAndReturn(wiki);
        final displayWiki = savedWiki ??
            wiki.copyWith(
              id: 'generated_${DateTime.now().millisecondsSinceEpoch}',
            );
        results = [displayWiki, ...results].take(maxResults).toList();
      }
    }

    final suggestions =
        await getHints(corrected, max: 6, cityName: resolvedCity);

    return SearchResult(
      correctedQuery: corrected,
      results: _dedupe(results).take(maxResults).toList(),
      suggestions: suggestions,
      detectedCity:
          resolvedCity ?? (results.isNotEmpty ? results.first.city : null),
      detectedCategory: detectedCategory,
    );
  }

  Future<SearchResult> searchPlaces({
    required String query,
    String? cityId,
    String? cityName,
    int maxResults = 10,
  }) =>
      search(
        query: query,
        cityId: cityId,
        cityName: cityName,
        maxResults: maxResults,
      );

  Future<List<String>> getHints(
    String query, {
    int max = 6,
    String? cityName,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final cacheKey = '$trimmed|${cityName ?? ''}';
    if (_lastHintKey == cacheKey && _lastHints.isNotEmpty) {
      return _lastHints.take(max).toList();
    }

    final index = await _getIndex();
    final lower = trimmed.toLowerCase();
    final hints = <String>{};

    for (final lm in index) {
      if (!_matchCity(lm, cityName)) continue;
      final name = lm.name.toLowerCase();
      if (name.startsWith(lower) ||
          name.contains(lower) ||
          _similarity(lower, name) >= 0.72) {
        hints.add(lm.name);
      }
    }

    for (final place in _famousPlaces) {
      final lowerPlace = place.toLowerCase();
      if (lowerPlace.contains(lower) ||
          _similarity(lower, lowerPlace) >= 0.72) {
        hints.add(place);
      }
    }

    final ordered = hints.toList()
      ..sort((a, b) {
        final sa = _hintScore(lower, a.toLowerCase());
        final sb = _hintScore(lower, b.toLowerCase());
        return sb.compareTo(sa);
      });

    _lastHintKey = cacheKey;
    _lastHints = ordered.take(max).toList();
    return _lastHints;
  }

  Future<List<String>> getSearchHints(
    String query, {
    int maxHints = 6,
    String? cityName,
  }) =>
      getHints(query, max: maxHints, cityName: cityName);

  Future<List<Landmark>> _getIndex() async {
    final now = DateTime.now();
    if (_index != null &&
        _indexTimestamp != null &&
        now.difference(_indexTimestamp!) <= _indexTtl) {
      return _index!;
    }

    final all = await _firebase.getAllLandmarks();
    final valid = all
        .where((lm) =>
            PlaceCategoryNormalizer.isAllowed(lm.category, contextText: lm.name))
        .map((lm) => lm.copyWith(
              category: PlaceCategoryNormalizer.normalize(
                lm.category,
                contextText: lm.name,
              ),
            ))
        .toList();

    for (final lm in valid) {
      if (!_cache.has(lm.id)) _cache.put(lm);
    }

    _index = _dedupe(valid);
    _indexTimestamp = now;
    return _index!;
  }

  String _resolveCorrectedQuery(String query, List<Landmark> index) {
    final lower = query.toLowerCase().trim();
    if (lower.isEmpty) return query;

    for (final entry in _aliases.entries) {
      if (entry.key == lower) return _titleCase(entry.key);
      for (final alias in entry.value) {
        if (lower == alias ||
            lower.contains(alias) ||
            alias.contains(lower) ||
            _similarity(lower, alias) >= 0.82) {
          return _titleCase(entry.key);
        }
      }
    }

    double best = 0;
    String? bestName;
    for (final lm in index) {
      final sim = _similarity(lower, lm.name.toLowerCase());
      if (sim > best) {
        best = sim;
        bestName = lm.name;
      }
    }

    if (best >= 0.78 && bestName != null) return bestName;
    return query;
  }

  List<Landmark> _applyFilters(
    List<Landmark> items, {
    String? cityId,
    String? cityName,
    String? category,
  }) {
    Iterable<Landmark> filtered = items;

    if ((cityId ?? '').trim().isNotEmpty) {
      filtered = filtered.where((e) => e.cityId.trim() == cityId!.trim());
    } else if ((cityName ?? '').trim().isNotEmpty) {
      final hint = cityName!.toLowerCase().trim();
      filtered = filtered.where((e) {
        final city = e.city.toLowerCase().trim();
        return city == hint || city.contains(hint) || hint.contains(city);
      });
    }

    if ((category ?? '').trim().isNotEmpty) {
      filtered = filtered.where((e) {
        final normalized =
            PlaceCategoryNormalizer.normalize(e.category, contextText: e.name);
        return normalized == category;
      });
    }

    return filtered.toList();
  }

  List<Landmark> _rank({
    required String query,
    required String rawQuery,
    required List<Landmark> landmarks,
    String? cityHint,
    String? categoryHint,
  }) {
    final sorted = [...landmarks]
      ..sort((a, b) => _score(b, query, rawQuery, cityHint, categoryHint)
          .compareTo(_score(a, query, rawQuery, cityHint, categoryHint)));
    return _dedupe(sorted);
  }

  double _score(
    Landmark lm,
    String query,
    String rawQuery,
    String? cityHint,
    String? categoryHint,
  ) {
    final name = lm.name.toLowerCase();
    final q = query.toLowerCase();
    final raw = rawQuery.toLowerCase();
    final city = lm.city.toLowerCase();
    final normCat =
        PlaceCategoryNormalizer.normalize(lm.category, contextText: lm.name);

    double score = 0;

    if (name == q) score += 120;
    if (name == raw) score += 90;
    if (name.startsWith(q)) score += 50;
    if (name.contains(q)) score += 35;
    if (q.contains(name) && name.length > 3) score += 25;
    score += _fieldHits(q, name) * 12;
    score += _similarity(q, name) * 35;
    score += _similarity(raw, name) * 20;

    final normalizedName = name.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    final normalizedQuery = q.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    if (normalizedName.contains(normalizedQuery) ||
        normalizedQuery.contains(normalizedName)) {
      score += 18;
    }

    for (final entry in _aliases.entries) {
      if (entry.key == name) {
        for (final alias in entry.value) {
          if (raw == alias ||
              q == alias ||
              raw.contains(alias) ||
              q.contains(alias)) {
            score += 35;
          }
        }
      }
    }

    if ((cityHint ?? '').trim().isNotEmpty) {
      final hint = cityHint!.toLowerCase().trim();
      if (city == hint || city.contains(hint) || hint.contains(city)) {
        score += 22;
      } else {
        score -= 8;
      }
    }

    if ((categoryHint ?? '').trim().isNotEmpty && normCat == categoryHint) {
      score += 12;
    }

    if (_famousPlaces.any((fp) => name == fp.toLowerCase())) score += 20;

    score += lm.rating * 2;
    if (lm.imageUrl.trim().isNotEmpty || lm.mediaUrls.isNotEmpty) score += 4;
    if (lm.wikipediaUrl?.isNotEmpty == true) score += 3;
    if (lm.lat != 0 && lm.lng != 0) score += 2;

    return score;
  }

  double _fieldHits(String query, String field) {
    final tokens = query.split(' ').where((t) => t.trim().length >= 3).toList();
    double hits = 0;
    for (final token in tokens) {
      if (field.contains(token)) hits++;
    }
    return hits;
  }

  String? _resolveCity(String query, String? userSelectedCity) {
    final lower = query.toLowerCase().trim();

    for (final entry in _canonicalCityMap.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }

    for (final entry in _cityNameMap.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }

    if ((userSelectedCity ?? '').trim().isNotEmpty &&
        userSelectedCity!.toLowerCase() != 'egypt') {
      return userSelectedCity.trim();
    }

    return null;
  }

  String? _detectCategory(String query) {
    final lower = query.toLowerCase();

    if (lower.contains('hotel') ||
        lower.contains('hotels') ||
        lower.contains('hostel') ||
        lower.contains('resort') ||
        lower.contains('فندق') ||
        lower.contains('فنادق') ||
        lower.contains('اوتيل') ||
        lower.contains('أوتيل')) {
      return 'hotel';
    }

    if (lower.contains('restaurant') ||
        lower.contains('restaurants') ||
        lower.contains('مطعم') ||
        lower.contains('مطاعم') ||
        lower.contains('food') ||
        lower.contains('eat') ||
        lower.contains('اكل') ||
        lower.contains('أكل')) {
      return 'restaurant';
    }

    if (lower.contains('cafe') ||
        lower.contains('cafes') ||
        lower.contains('coffee') ||
        lower.contains('كافيه') ||
        lower.contains('كافيهات') ||
        lower.contains('قهوة') ||
        lower.contains('مقهى')) {
      return 'cafe';
    }

    if (lower.contains('outing') ||
        lower.contains('outings') ||
        lower.contains('park') ||
        lower.contains('parks') ||
        lower.contains('garden') ||
        lower.contains('mall') ||
        lower.contains('cinema') ||
        lower.contains('beach') ||
        lower.contains('فسح') ||
        lower.contains('فسحة') ||
        lower.contains('خروجات') ||
        lower.contains('خروجة') ||
        lower.contains('حديقة') ||
        lower.contains('حدائق') ||
        lower.contains('مول') ||
        lower.contains('سينما')) {
      return 'outing';
    }

    return null;
  }

  Future<List<Landmark>> _generateFromNearbyProvider({
    required String category,
    required String? cityName,
    required String rawQuery,
    required int maxResults,
    bool preferNameMatch = false,
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
    print(
      '[SearchEngine] provider generate: category=$category city=$resolvedCity '
      'lat=${coords.lat} lng=${coords.lng} categories=$nearbyCategories',
    );

    final places = await _nearby.getNearbyForCoordinates(
      lat: coords.lat,
      lng: coords.lng,
      categories: nearbyCategories,
      limit: maxResults * 3,
    );

    print('[SearchEngine] provider returned ${places.length} places');

    if (places.isEmpty) return [];

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

      final landmark = Landmark(
        id: '',
        name: place.name.trim(),
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
          'mapsUrl': place.mapsUrl,
          if (place.website != null) 'website': place.website,
          if (place.bookingUrl != null) 'bookingUrl': place.bookingUrl,
        },
      );

      final saved = await _safePersistAndReturn(landmark);
      generated.add(saved ?? landmark.copyWith(id: 'generated_${DateTime.now().microsecondsSinceEpoch}'));

      if (generated.length >= maxResults) break;
    }

    return _dedupe(generated);
  }

  List<String> _nearbyCategoriesFor(String category) {
    switch (category) {
      case 'hotel':
        return const ['hotel'];
      case 'restaurant':
        return const ['restaurant'];
      case 'cafe':
        return const ['cafe'];
      case 'tourist':
        return const ['tourist', 'attraction'];
      case 'outing':
        // Some versions of NearbyService use "attraction", newer ones use "outing".
        return const ['outing', 'tourist', 'attraction'];
      default:
        return [category];
    }
  }

  String _normalizeProviderCategory({
    required String requestedCategory,
    required String providerCategory,
    required List<String> providerTypes,
    required String name,
  }) {
    if (requestedCategory == 'outing') {
      final text = '$providerCategory ${providerTypes.join(' ')} $name';
      final lower = text.toLowerCase();
      if (lower.contains('park') ||
          lower.contains('garden') ||
          lower.contains('mall') ||
          lower.contains('cinema') ||
          lower.contains('theatre') ||
          lower.contains('theater') ||
          lower.contains('beach') ||
          lower.contains('leisure') ||
          lower.contains('tourism') ||
          lower.contains('attraction') ||
          lower.contains('viewpoint') ||
          lower.contains('zoo') ||
          lower.contains('aquarium')) {
        return 'outing';
      }
      return PlaceCategoryNormalizer.normalize(providerCategory, contextText: text);
    }

    return PlaceCategoryNormalizer.normalize(
      providerCategory,
      contextText: '${providerTypes.join(' ')} $name',
    );
  }

  Future<({double lat, double lng})?> _resolveCityCoordinates(String cityName) async {
    final clean = cityName.trim();
    if (clean.isEmpty) return null;

    try {
      final city = await _firebase.getCityByName(clean);
      if (city != null && city.lat != 0 && city.lng != 0) {
        return (lat: city.lat, lng: city.lng);
      }
    } catch (_) {}

    final canonical = _cityNameMap[clean.toLowerCase()] ?? clean;
    return _cityCoordinates[canonical];
  }

  Future<Landmark?> _fetchWikipediaLandmark({
    required String query,
    required String rawQuery,
    String? cityName,
    String? category,
    required List<Landmark> existingResults,
  }) async {
    try {
      final cityHint = (cityName ?? '').trim();

      final variants = <String>{
        if (cityHint.isNotEmpty) '$query $cityHint Egypt',
        if (cityHint.isNotEmpty) '$rawQuery $cityHint Egypt',
        '$query Egypt',
        '$rawQuery Egypt',
        ..._queryVariants(query).map((v) =>
            cityHint.isNotEmpty ? '$v $cityHint Egypt' : '$v Egypt'),
        ..._queryVariants(rawQuery).map((v) =>
            cityHint.isNotEmpty ? '$v $cityHint Egypt' : '$v Egypt'),
      }.where((e) => e.trim().isNotEmpty).toList();

      for (final q in variants) {
        final result = await _wikipedia.search(
          q,
          cityName: cityHint.isNotEmpty ? cityHint : null,
        );
        if (result == null) continue;

        final textForCity =
            '${result.title} ${result.summary} ${result.fullText} $q $query $rawQuery';

        final canonicalCity =
            _resolveCity(textForCity, cityName) ??
            _inferCityFromKnownPlace(textForCity) ??
            cityName;

        if ((canonicalCity ?? '').trim().isEmpty ||
            canonicalCity!.toLowerCase() == 'egypt') {
          print("[SearchEngine] rejected wiki result with no Egyptian city: ${result.title}");
          continue;
        }

        if (!_isEgyptianResult(
          title: result.title,
          description: '${result.summary} ${result.fullText}',
          cityName: canonicalCity,
          query: q,
        )) {
          print("[SearchEngine] rejected non-Egypt wiki result: ${result.title}");
          continue;
        }

        final landmark = Landmark(
          id: '',
          name: result.title.trim(),
          cityId: '',
          city: canonicalCity,
          category: category ??
              PlaceCategoryNormalizer.normalize(
                '',
                contextText: '${result.title} ${result.summary}',
              ),
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

  Future<Landmark?> _fetchOsmTextSearchLandmark({
    required String query,
    required String rawQuery,
    String? category,
    String? cityName,
    required List<Landmark> existingResults,
  }) async {
    try {
      final searchText = [
        rawQuery,
        if ((cityName ?? '').trim().isNotEmpty) cityName!.trim(),
        'Egypt',
      ].join(' ');

      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'q': searchText,
        'countrycodes': 'eg',
        'addressdetails': '1',
        'limit': '8',
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
        final inferredCategory = category ??
            PlaceCategoryNormalizer.normalize(
              classText,
              contextText: '$displayName $typeText',
            );

        if (!PlaceCategoryNormalizer.isAllowed(
          inferredCategory,
          contextText: displayName,
        )) {
          continue;
        }

        if (category != null) {
          final normalized = PlaceCategoryNormalizer.normalize(
            inferredCategory,
            contextText: '$displayName $typeText $classText',
          );
          if (normalized != category) continue;
        }

        final score = _looseNameScore(displayName, rawQuery) +
            _looseNameScore(displayName, query) +
            ((cityName ?? '').trim().isNotEmpty &&
                    displayName.toLowerCase().contains(cityName!.toLowerCase())
                ? 0.25
                : 0);

        if (score > bestScore) {
          bestScore = score;
          best = map;
        }
      }

      if (best == null || bestScore < 0.42) return null;

      final displayName = (best['display_name'] ?? '').toString();
      final cleanName = _cleanOsmDisplayName(displayName, rawQuery);
      final lat = double.tryParse((best['lat'] ?? '').toString()) ?? 0;
      final lng = double.tryParse((best['lon'] ?? '').toString()) ?? 0;
      if (lat == 0 || lng == 0) return null;

      final address = Map<String, dynamic>.from(best['address'] as Map? ?? {});
      final resolvedCity = _cityFromOsmAddress(address) ??
          _resolveCity(displayName, cityName) ??
          cityName ??
          'Egypt';

      final inferredCategory = category ??
          PlaceCategoryNormalizer.normalize(
            (best['class'] ?? '').toString(),
            contextText: '$displayName ${(best['type'] ?? '').toString()}',
          );

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
        },
      );

      if (_containsEquivalent(existingResults, landmark)) return null;
      return landmark;
    } catch (e) {
      print('[SearchEngine] OSM text fallback error: $e');
      return null;
    }
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
    return parts.first;
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
      final resolved = _resolveCity(text, null) ?? text;
      if (resolved.toLowerCase() != 'egypt') return resolved;
    }
    return null;
  }

  bool _isGenericCategoryQuery(String query, String category, String? cityName) {
    final normalized = _normalizeSearchText(query);
    final city = _normalizeSearchText(cityName ?? '');

    final tokensToRemove = <String>{
      ..._categoryWords(category),
      'in',
      'near',
      'around',
      'egypt',
      'في',
      'داخل',
      'قريب',
      'قريبة',
      if (city.isNotEmpty) ...city.split(' '),
    };

    final remaining = normalized
        .split(' ')
        .where((t) => t.trim().isNotEmpty && !tokensToRemove.contains(t))
        .toList();

    return remaining.isEmpty || remaining.join('').length <= 2;
  }

  Set<String> _categoryWords(String category) {
    switch (category) {
      case 'hotel':
        return {'hotel', 'hotels', 'hostel', 'resort', 'فندق', 'فنادق', 'اوتيل'};
      case 'restaurant':
        return {'restaurant', 'restaurants', 'food', 'eat', 'مطعم', 'مطاعم', 'اكل'};
      case 'cafe':
        return {'cafe', 'cafes', 'coffee', 'كافيه', 'كافيهات', 'قهوة', 'مقهى'};
      case 'tourist':
        return {'tourist', 'attraction', 'landmark', 'museum', 'temple', 'مزار', 'معلم', 'متحف'};
      case 'outing':
        return {'outing', 'outings', 'park', 'parks', 'garden', 'mall', 'cinema', 'beach', 'فسح', 'خروجات', 'حديقة', 'مول'};
      default:
        return {category};
    }
  }

  bool _isLooseNameMatch(String candidate, String query) {
    return _looseNameScore(candidate, query) >= 0.42;
  }

  double _looseNameScore(String candidate, String query) {
    final c = _normalizeSearchText(candidate);
    final q = _normalizeSearchText(query);
    if (c.isEmpty || q.isEmpty) return 0;
    if (c == q) return 1;
    if (c.contains(q) || q.contains(c)) return 0.95;

    final qTokens = q
        .split(' ')
        .where((e) => e.length > 2 && !_allCategoryStopWords.contains(e))
        .toList();
    final cTokens = c.split(' ').where((e) => e.length > 2).toList();
    if (qTokens.isEmpty || cTokens.isEmpty) return _similarity(q, c);

    var matched = 0.0;
    for (final qt in qTokens) {
      var best = 0.0;
      for (final ct in cTokens) {
        if (ct == qt || ct.contains(qt) || qt.contains(ct)) {
          best = 1;
          break;
        }
        final sim = _similarity(qt, ct);
        if (sim > best) best = sim;
      }
      if (best >= 0.62) matched += best;
    }

    final tokenScore = matched / qTokens.length;
    final fullScore = _similarity(q, c);
    return tokenScore > fullScore ? tokenScore : fullScore;
  }

  static const Set<String> _allCategoryStopWords = {
    'hotel', 'hotels', 'hostel', 'resort',
    'restaurant', 'restaurants', 'food', 'eat',
    'cafe', 'cafes', 'coffee',
    'tourist', 'attraction', 'landmark', 'museum', 'temple',
    'outing', 'outings', 'park', 'parks', 'garden', 'mall', 'cinema', 'beach',
    'egypt', 'near', 'around', 'inside', 'best', 'top',
    'فندق', 'فنادق', 'مطعم', 'مطاعم', 'كافيه', 'كافيهات', 'حديقة', 'مول',
  };

  String _normalizeSearchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _queryVariants(String query) {
    final q = query.trim();
    if (q.isEmpty) return [];

    final lower = q.toLowerCase();
    final variants = <String>{q};

    void addReversedPattern(String suffix, String prefix) {
      if (lower.endsWith(' $suffix')) {
        final base = q.substring(0, q.length - suffix.length).trim();
        if (base.isNotEmpty) {
          variants.add('$prefix of $base');
          variants.add(base);
        }
      }

      final prefixOf = '$prefix of ';
      if (lower.startsWith(prefixOf.toLowerCase())) {
        final base = q.substring(prefixOf.length).trim();
        if (base.isNotEmpty) {
          variants.add('$base $suffix');
          variants.add(base);
        }
      }
    }

    addReversedPattern('temple', 'Temple');
    addReversedPattern('citadel', 'Citadel');
    addReversedPattern('museum', 'Museum');
    addReversedPattern('palace', 'Palace');
    addReversedPattern('castle', 'Castle');

    return variants.toList();
  }

  String? _inferCityFromKnownPlace(String text) {
    final lower = text.toLowerCase();

    const known = {
      'montaza': 'Alexandria',
      'montazah': 'Alexandria',
      'qaitbay': 'Alexandria',
      'bibliotheca': 'Alexandria',
      'alexandria library': 'Alexandria',
      'kom el shoqafa': 'Alexandria',
      'catacombs': 'Alexandria',
      'edfu': 'Aswan',
      'kom ombo': 'Aswan',
      'philae': 'Aswan',
      'abu simbel': 'Aswan',
      'karnak': 'Luxor',
      'luxor temple': 'Luxor',
      'valley of the kings': 'Luxor',
      'hatshepsut': 'Luxor',
      'pyramid': 'Giza',
      'sphinx': 'Giza',
      'grand egyptian museum': 'Giza',
      'khan el-khalili': 'Cairo',
      'egyptian museum': 'Cairo',
      'cairo tower': 'Cairo',
      'citadel of cairo': 'Cairo',
      'siwa': 'Siwa',
      'blue hole': 'Dahab',
      'ras mohammed': 'Sharm El Sheikh',
      'hurghada': 'Hurghada',
    };

    for (final entry in known.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }

    return null;
  }

  bool _isEgyptianResult({
    required String title,
    required String description,
    required String cityName,
    required String query,
  }) {
    final text = '$title $description $cityName $query'.toLowerCase();
    final city = cityName.trim().toLowerCase();

    const egyptSignals = [
      'egypt',
      'egyptian',
      'cairo',
      'giza',
      'luxor',
      'aswan',
      'alexandria',
      'beheira',
      'faiyum',
      'fayoum',
      'saqqara',
      'dahshur',
      'minya',
      'sohag',
      'qena',
      'beni suef',
      'ismailia',
      'port said',
      'suez',
      'damietta',
      'sharqia',
      'kafr el sheikh',
      'monufia',
      'gharbia',
      'matrouh',
      'red sea',
      'new valley',
      'north sinai',
      'south sinai',
      'sinai',
      'hurghada',
      'sharm',
      'dahab',
      'siwa',
    ];

    final hasEgyptSignal = egyptSignals.any(text.contains);
    final hasCitySignal = city.isNotEmpty && text.contains(city);

    return hasEgyptSignal || hasCitySignal;
  }

  bool _containsEquivalent(List<Landmark> items, Landmark candidate) {
    final cname = candidate.name.trim().toLowerCase();
    final ccity = candidate.city.trim().toLowerCase();
    return items.any((e) {
      final name = e.name.trim().toLowerCase();
      final city = e.city.trim().toLowerCase();
      return name == cname &&
          (city == ccity || city.contains(ccity) || ccity.contains(city));
    });
  }

  Future<Landmark?> _safePersistAndReturn(Landmark landmark) async {
    try {
      if (landmark.city.trim().isEmpty ||
          landmark.city.trim().toLowerCase() == 'egypt') {
        return null;
      }

      final docId = await _firebase.saveLandmark(landmark);
      final saved = landmark.copyWith(id: docId);
      _cache.merge(saved);

      _indexTimestamp = null;
      _index = null;
      return saved;
    } catch (e) {
      print('[SearchEngine] persist failed: $e');
      return null;
    }
  }

  bool _isStrongNameMatch(Landmark lm, String corrected, String raw) {
    final name = lm.name.trim().toLowerCase();
    final q = corrected.trim().toLowerCase();
    final r = raw.trim().toLowerCase();

    if (name == q || name == r) return true;
    if (name.contains(q) || q.contains(name)) return true;
    if (name.contains(r) || r.contains(name)) return true;
    if (_similarity(q, name) >= 0.82) return true;
    if (_similarity(r, name) >= 0.82) return true;

    for (final entry in _aliases.entries) {
      if (entry.key == name) {
        for (final alias in entry.value) {
          if (alias == q ||
              alias == r ||
              q.contains(alias) ||
              r.contains(alias)) {
            return true;
          }
        }
      }
    }

    return false;
  }

  List<Landmark> _dedupe(List<Landmark> items) {
    final seen = <String>{};
    final result = <Landmark>[];
    for (final lm in items) {
      final key =
          '${lm.name.trim().toLowerCase()}|${lm.city.trim().toLowerCase()}';
      if (seen.add(key)) result.add(lm);
    }
    return result;
  }

  bool _matchCity(Landmark lm, String? cityName) {
    if ((cityName ?? '').trim().isEmpty) return true;
    final city = lm.city.toLowerCase().trim();
    final hint = cityName!.toLowerCase().trim();
    return city == hint || city.contains(hint) || hint.contains(city);
  }

  int _hintScore(String q, String candidate) {
    var score = 0;
    if (candidate.startsWith(q)) score += 10;
    if (candidate.contains(q)) score += 6;
    score += (_similarity(q, candidate) * 10).round();
    return score;
  }

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final distance = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
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
        final cost = s[i - 1] == t[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    return dp[m][n];
  }

  String _titleCase(String value) {
    return value
        .split(' ')
        .map((word) =>
            word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }
}
