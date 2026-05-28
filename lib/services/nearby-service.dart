// ============================================================
//  services/nearby-service.dart
//  MULTI-SOURCE FREE VERSION — Firebase-first helper + free APIs
//
//  Sources order used by the UI:
//  1) Stored nearby places from Landmark/Firebase
//  2) Free Nominatim text search
//  3) Free Overpass live search as last source only
//
//  Notes:
//  - No Google Places API / no billing.
//  - Includes outing places: parks, gardens, malls, cinemas, theatres, zoos,
//    aquariums, theme parks, sports/leisure places.
//  - Safe timeouts + cooldown to avoid long UI blocking.
//  - Strong dedupe by normalized name + category.
// ============================================================

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geoguide/constants/constants.dart';
import 'package:http/http.dart' as http;

class NearbyPlace {
  final String placeId;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double distanceKm;
  final double rating;
  final int userRatingsTotal;
  final String priceLevel;
  final bool isOpenNow;
  final bool hasOpeningHours;
  final String imageUrl;
  final String category;
  final List<String> types;
  final String mapsUrl;
  final String? bookingUrl;
  final String? wikipediaUrl;
  final String? phone;
  final String? website;
  final DateTime? fetchedAt;

  const NearbyPlace({
    required this.placeId,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.distanceKm,
    required this.rating,
    required this.userRatingsTotal,
    required this.priceLevel,
    required this.isOpenNow,
    required this.hasOpeningHours,
    required this.imageUrl,
    required this.category,
    required this.types,
    required this.mapsUrl,
    this.bookingUrl,
    this.wikipediaUrl,
    this.phone,
    this.website,
    this.fetchedAt,
  });

  factory NearbyPlace.fromJson(Map<String, dynamic> json) {
    return NearbyPlace(
      placeId: (json['placeId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      lat: ((json['lat'] ?? 0) as num).toDouble(),
      lng: ((json['lng'] ?? 0) as num).toDouble(),
      distanceKm: ((json['distanceKm'] ?? 0) as num).toDouble(),
      rating: ((json['rating'] ?? 0) as num).toDouble(),
      userRatingsTotal: ((json['userRatingsTotal'] ?? 0) as num).toInt(),
      priceLevel: (json['priceLevel'] ?? '').toString(),
      isOpenNow: (json['isOpenNow'] ?? false) as bool,
      hasOpeningHours: (json['hasOpeningHours'] ?? false) as bool,
      imageUrl: (json['imageUrl'] ?? '').toString(),
      category: _normalizeCategory((json['category'] ?? 'tourist').toString()),
      types: List<String>.from(json['types'] as List? ?? const []),
      mapsUrl: (json['mapsUrl'] ?? '').toString(),
      bookingUrl: json['bookingUrl']?.toString(),
      wikipediaUrl: json['wikipediaUrl']?.toString(),
      phone: json['phone']?.toString(),
      website: json['website']?.toString(),
      fetchedAt: json['fetchedAt'] != null
          ? DateTime.tryParse(json['fetchedAt'].toString())
          : null,
    );
  }

  factory NearbyPlace.fromOsm({
    required Map<String, dynamic> element,
    required double originLat,
    required double originLng,
  }) {
    final tags = Map<String, dynamic>.from(element['tags'] as Map? ?? {});

    double lat = 0;
    double lng = 0;

    if (element['lat'] != null && element['lon'] != null) {
      lat = ((element['lat'] ?? 0) as num).toDouble();
      lng = ((element['lon'] ?? 0) as num).toDouble();
    } else if (element['center'] is Map) {
      final center = Map<String, dynamic>.from(element['center'] as Map);
      lat = ((center['lat'] ?? 0) as num).toDouble();
      lng = ((center['lon'] ?? 0) as num).toDouble();
    }

    final category = _detectCategory(tags);
    final address = _buildAddress(tags);
    final website = _extractWebsite(tags);
    final type = (element['type'] ?? 'osm').toString();
    final osmId = (element['id'] ?? '').toString();

    return NearbyPlace(
      placeId: '${type}_$osmId',
      name: (tags['name:en'] ?? tags['name'] ?? '').toString().trim(),
      address: address,
      lat: lat,
      lng: lng,
      distanceKm: _distanceKm(originLat, originLng, lat, lng),
      rating: 0,
      userRatingsTotal: 0,
      priceLevel: '',
      isOpenNow: false,
      hasOpeningHours: tags['opening_hours'] != null,
      imageUrl: '',
      category: category,
      types: tags.entries.map((e) => '${e.key}:${e.value}').toList(),
      mapsUrl: _buildMapsUrl(lat, lng),
      bookingUrl: _buildBookingUrl(category: category, website: website),
      wikipediaUrl: _extractWikipediaUrl(tags),
      phone: _extractPhone(tags),
      website: website,
      fetchedAt: DateTime.now(),
    );
  }

  factory NearbyPlace.fromNominatim({
    required Map<String, dynamic> item,
    required double originLat,
    required double originLng,
    required String category,
  }) {
    final lat = double.tryParse((item['lat'] ?? '0').toString()) ?? 0;
    final lng = double.tryParse((item['lon'] ?? '0').toString()) ?? 0;
    final name = _extractNominatimName(item);
    final address = (item['display_name'] ?? '').toString();

    final osmType = (item['osm_type'] ?? 'nominatim').toString();
    final osmId = (item['osm_id'] ?? '').toString();

    return NearbyPlace(
      placeId: 'nominatim_${osmType}_$osmId',
      name: name,
      address: address,
      lat: lat,
      lng: lng,
      distanceKm: _distanceKm(originLat, originLng, lat, lng),
      rating: 0,
      userRatingsTotal: 0,
      priceLevel: '',
      isOpenNow: false,
      hasOpeningHours: false,
      imageUrl: '',
      category: _normalizeCategory(category),
      types: [
        'source:nominatim',
        'class:${item['class'] ?? ''}',
        'type:${item['type'] ?? ''}',
      ],
      mapsUrl: _buildMapsUrl(lat, lng),
      bookingUrl: null,
      wikipediaUrl: null,
      phone: null,
      website: null,
      fetchedAt: DateTime.now(),
    );
  }

  static String _extractNominatimName(Map<String, dynamic> item) {
    final namedetails =
        Map<String, dynamic>.from(item['namedetails'] as Map? ?? {});
    final direct = (namedetails['name:en'] ??
            namedetails['name'] ??
            item['name'] ??
            '')
        .toString()
        .trim();

    if (direct.isNotEmpty) return direct;

    final display = (item['display_name'] ?? '').toString().trim();
    if (display.isEmpty) return '';
    return display.split(',').first.trim();
  }

  Map<String, dynamic> toJson() {
    return {
      'placeId': placeId,
      'name': name,
      'address': address,
      'lat': lat,
      'lng': lng,
      'distanceKm': distanceKm,
      'rating': rating,
      'userRatingsTotal': userRatingsTotal,
      'priceLevel': priceLevel,
      'isOpenNow': isOpenNow,
      'hasOpeningHours': hasOpeningHours,
      'imageUrl': imageUrl,
      'category': _normalizeCategory(category),
      'types': types,
      'mapsUrl': mapsUrl,
      'bookingUrl': bookingUrl,
      'wikipediaUrl': wikipediaUrl,
      'phone': phone,
      'website': website,
      'fetchedAt': fetchedAt?.toIso8601String(),
    };
  }

  NearbyPlace copyWith({
    String? placeId,
    String? name,
    String? address,
    double? lat,
    double? lng,
    double? distanceKm,
    double? rating,
    int? userRatingsTotal,
    String? priceLevel,
    bool? isOpenNow,
    bool? hasOpeningHours,
    String? imageUrl,
    String? category,
    List<String>? types,
    String? mapsUrl,
    String? bookingUrl,
    String? wikipediaUrl,
    String? phone,
    String? website,
    DateTime? fetchedAt,
  }) {
    return NearbyPlace(
      placeId: placeId ?? this.placeId,
      name: name ?? this.name,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      distanceKm: distanceKm ?? this.distanceKm,
      rating: rating ?? this.rating,
      userRatingsTotal: userRatingsTotal ?? this.userRatingsTotal,
      priceLevel: priceLevel ?? this.priceLevel,
      isOpenNow: isOpenNow ?? this.isOpenNow,
      hasOpeningHours: hasOpeningHours ?? this.hasOpeningHours,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      types: types ?? this.types,
      mapsUrl: mapsUrl ?? this.mapsUrl,
      bookingUrl: bookingUrl ?? this.bookingUrl,
      wikipediaUrl: wikipediaUrl ?? this.wikipediaUrl,
      phone: phone ?? this.phone,
      website: website ?? this.website,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }

  static String _normalizeCategory(String raw) {
    final cat = raw.trim().toLowerCase();

    if (cat.contains('hotel') ||
        cat.contains('hostel') ||
        cat.contains('guest_house') ||
        cat.contains('guest house') ||
        cat.contains('motel') ||
        cat.contains('resort') ||
        cat.contains('apartment')) {
      return 'hotel';
    }

    if (cat.contains('cafe') ||
        cat.contains('coffee') ||
        cat.contains('bakery') ||
        cat.contains('pastry') ||
        cat.contains('dessert') ||
        cat.contains('ice_cream') ||
        cat.contains('ice cream')) {
      return 'cafe';
    }

    if (cat.contains('restaurant') ||
        cat.contains('fast_food') ||
        cat.contains('fast food') ||
        cat.contains('food_court') ||
        cat.contains('food court')) {
      return 'restaurant';
    }

    if (cat.contains('outing') ||
        cat.contains('park') ||
        cat.contains('garden') ||
        cat.contains('mall') ||
        cat.contains('cinema') ||
        cat.contains('theatre') ||
        cat.contains('beach') ||
        cat.contains('leisure') ||
        cat.contains('zoo') ||
        cat.contains('aquarium') ||
        cat.contains('theme_park') ||
        cat.contains('theme park')) {
      return 'outing';
    }

    if (cat.contains('tourist') ||
        cat.contains('attraction') ||
        cat.contains('museum') ||
        cat.contains('viewpoint') ||
        cat.contains('historic') ||
        cat.contains('gallery')) {
      return 'tourist';
    }

    return 'tourist';
  }

  static String _detectCategory(Map<String, dynamic> tags) {
    final amenity = (tags['amenity'] ?? '').toString().toLowerCase();
    final tourism = (tags['tourism'] ?? '').toString().toLowerCase();
    final historic = (tags['historic'] ?? '').toString().toLowerCase();
    final leisure = (tags['leisure'] ?? '').toString().toLowerCase();
    final shop = (tags['shop'] ?? '').toString().toLowerCase();

    if (tourism == 'hotel' ||
        tourism == 'hostel' ||
        tourism == 'guest_house' ||
        tourism == 'motel' ||
        tourism == 'apartment' ||
        tourism == 'resort') {
      return 'hotel';
    }

    if (amenity == 'cafe' ||
        amenity == 'coffee_shop' ||
        amenity == 'ice_cream' ||
        shop == 'coffee' ||
        shop == 'bakery' ||
        shop == 'pastry' ||
        shop == 'confectionery') {
      return 'cafe';
    }

    if (amenity == 'restaurant' ||
        amenity == 'fast_food' ||
        amenity == 'food_court' ||
        amenity == 'bar' ||
        amenity == 'pub') {
      return 'restaurant';
    }

    if (leisure == 'park' ||
        leisure == 'garden' ||
        leisure == 'playground' ||
        leisure == 'beach_resort' ||
        leisure == 'sports_centre' ||
        leisure == 'fitness_centre' ||
        amenity == 'cinema' ||
        amenity == 'theatre' ||
        amenity == 'arts_centre' ||
        amenity == 'community_centre' ||
        amenity == 'fountain' ||
        shop == 'mall' ||
        shop == 'department_store' ||
        tourism == 'theme_park' ||
        tourism == 'zoo' ||
        tourism == 'aquarium' ||
        tourism == 'picnic_site') {
      return 'outing';
    }

    if (tourism == 'museum' ||
        tourism == 'attraction' ||
        tourism == 'viewpoint' ||
        tourism == 'gallery' ||
        historic.isNotEmpty) {
      return 'tourist';
    }

    return 'tourist';
  }

  static String _buildAddress(Map<String, dynamic> tags) {
    final parts = <String>[
      (tags['addr:street'] ?? '').toString().trim(),
      (tags['addr:housenumber'] ?? '').toString().trim(),
      (tags['addr:suburb'] ?? '').toString().trim(),
      (tags['addr:city'] ?? '').toString().trim(),
    ].where((e) => e.isNotEmpty).toList();

    if (parts.isNotEmpty) return parts.join(', ');
    return (tags['name:en'] ?? tags['name'] ?? '').toString().trim();
  }

  static String _buildMapsUrl(double lat, double lng) {
    return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
  }

  static String? _extractWebsite(Map<String, dynamic> tags) {
    final raw = (tags['website'] ??
            tags['contact:website'] ??
            tags['url'] ??
            '')
        .toString()
        .trim();

    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return 'https://$raw';
  }

  static String? _extractPhone(Map<String, dynamic> tags) {
    final raw =
        (tags['phone'] ?? tags['contact:phone'] ?? '').toString().trim();
    return raw.isEmpty ? null : raw;
  }

  static String? _extractWikipediaUrl(Map<String, dynamic> tags) {
    final raw = (tags['wikipedia'] ?? '').toString().trim();
    if (raw.isEmpty) return null;

    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    if (raw.contains(':')) {
      final parts = raw.split(':');
      if (parts.length >= 2) {
        final lang = parts.first.trim();
        final title = parts.sublist(1).join(':').trim().replaceAll(' ', '_');
        return 'https://$lang.wikipedia.org/wiki/$title';
      }
    }

    return null;
  }

  static String? _buildBookingUrl({
    required String category,
    required String? website,
  }) {
    if (website == null || website.trim().isEmpty) return null;
    if (category == 'hotel') return website;
    if (category == 'restaurant' || category == 'cafe') return website;
    return null;
  }

  static double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    if (lat1 == 0 || lng1 == 0 || lat2 == 0 || lng2 == 0) return 9999;

    const earthRadiusKm = 6371.0;

    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degToRad(double deg) => deg * math.pi / 180.0;
}

class NearbyUpdateResult {
  final List<NearbyPlace> places;
  final bool didRefresh;
  final DateTime refreshedAt;

  const NearbyUpdateResult({
    required this.places,
    required this.didRefresh,
    required this.refreshedAt,
  });
}

class NearbyService {
  NearbyService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final Map<String, List<NearbyPlace>> _nearbyMemoryCache = {};
  static DateTime? _overpassCooldownUntil;
  static DateTime? _nominatimCooldownUntil;

  static const Duration _overpassHttpTimeout = Duration(seconds: 6);
  static const Duration _nominatimTimeout = Duration(seconds: 10);
  static const Duration _cooldownDuration = Duration(seconds: 45);

  static const List<String> _overpassEndpoints = [
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass-api.de/api/interpreter',
    'https://overpass.openstreetmap.ru/api/interpreter',
  ];

  bool shouldRefresh(DateTime? lastFetchedAt) {
    if (lastFetchedAt == null) return true;
    return DateTime.now().difference(lastFetchedAt) >= AppConstants.nearbyTtl;
  }

  DateTime? getLatestFetchedAt(List<NearbyPlace> places) {
    DateTime? latest;

    for (final place in places) {
      final fetchedAt = place.fetchedAt;
      if (fetchedAt == null) continue;

      if (latest == null || fetchedAt.isAfter(latest)) {
        latest = fetchedAt;
      }
    }

    return latest;
  }

  Future<NearbyUpdateResult> getNearbyWithAutoRefresh({
    required double lat,
    required double lng,
    required String cityName,
    List<NearbyPlace> existingPlaces = const [],
    List<String> categories = const [
      'hotel',
      'restaurant',
      'cafe',
      'tourist',
      'outing',
    ],
    int limit = 24,
    DateTime? lastFetchedAt,
    bool forceRefresh = false,
  }) async {
    final latest = lastFetchedAt ?? getLatestFetchedAt(existingPlaces);
    final needsRefresh = forceRefresh || shouldRefresh(latest);

    final existingSorted = [...existingPlaces]
      ..sort((a, b) => _rankScore(b).compareTo(_rankScore(a)));

    if (!needsRefresh && existingSorted.isNotEmpty) {
      return NearbyUpdateResult(
        places: existingSorted.take(limit).toList(),
        didRefresh: false,
        refreshedAt: latest ?? DateTime.now(),
      );
    }

    final fresh = await getNearbyForCoordinates(
      lat: lat,
      lng: lng,
      cityName: cityName,
      categories: categories,
      limit: math.max(limit, 32),
      forceRefresh: forceRefresh,
    );

    if (fresh.isEmpty && existingSorted.isNotEmpty) {
      return NearbyUpdateResult(
        places: existingSorted.take(limit).toList(),
        didRefresh: false,
        refreshedAt: latest ?? DateTime.now(),
      );
    }

    final merged = mergeNearbyPlaces(
      oldPlaces: existingSorted,
      newPlaces: fresh,
      limit: limit,
    );

    return NearbyUpdateResult(
      places: merged,
      didRefresh: fresh.isNotEmpty,
      refreshedAt: fresh.isNotEmpty ? DateTime.now() : (latest ?? DateTime.now()),
    );
  }

  Future<List<NearbyPlace>> getNearbyForCoordinates({
    required double lat,
    required double lng,
    required String cityName,
    List<String> categories = const [
      'hotel',
      'restaurant',
      'cafe',
      'tourist',
      'outing',
    ],
    int limit = 36,
    bool forceRefresh = false,
  }) async {
    if (lat == 0 || lng == 0) return [];

    final normalizedCategories = categories
        .map((e) => NearbyPlace._normalizeCategory(e))
        .toSet()
        .toList()
      ..sort();

    final cacheKey =
        '${lat.toStringAsFixed(4)}|${lng.toStringAsFixed(4)}|${_normalizeText(cityName)}|${normalizedCategories.join(',')}|$limit';

    final cachedNearby = _nearbyMemoryCache[cacheKey];
    if (!forceRefresh && cachedNearby != null && cachedNearby.isNotEmpty) {
      return cachedNearby.take(limit).toList();
    }

    final collected = <NearbyPlace>[];
    final seen = <String>{};

    Future<void> addAll(List<NearbyPlace> places) async {
      for (final place in places) {
        if (place.name.trim().isEmpty) continue;
        if (place.distanceKm > 25.0) continue;
        final key = _dedupeKey(place);
        if (seen.add(key)) collected.add(place);
      }
    }

    // Free text search first. It is lighter than wide Overpass scans and helps
    // with outing places such as malls, parks, cinemas, zoos.
    final textResults = await _fetchFromNominatim(
      lat: lat,
      lng: lng,
      cityName: cityName,
      categories: normalizedCategories,
      limit: math.max(limit, 32),
    );
    await addAll(textResults);

    // Overpass is last live source only. It can timeout in busy areas.
    if (collected.length < math.min(limit, 18)) {
      final overpassResults = await _fetchFromOverpassProgressive(
        lat: lat,
        lng: lng,
        categories: normalizedCategories,
        limit: math.max(limit, 32),
      );
      await addAll(overpassResults);
    }

    collected.sort((a, b) => _rankScore(b).compareTo(_rankScore(a)));

    final finalNearby = collected.take(limit).toList();

    if (finalNearby.isNotEmpty) {
      _nearbyMemoryCache[cacheKey] = finalNearby;
    }

    return finalNearby;
  }

  Future<List<NearbyPlace>> _fetchFromNominatim({
    required double lat,
    required double lng,
    required String cityName,
    required List<String> categories,
    required int limit,
  }) async {
    if (_isNominatimCoolingDown) {
      if (kDebugMode) {
        debugPrint('[Nearby] Nominatim cooling down; skip text search.');
      }
      return const [];
    }

    final queries = _buildNominatimQueries(cityName, categories);
    final collected = <NearbyPlace>[];
    final seen = <String>{};

    for (final q in queries) {
      if (collected.length >= limit) break;

      try {
        final uri = Uri.https(
          'nominatim.openstreetmap.org',
          '/search',
          {
            'q': q,
            'format': 'jsonv2',
            'addressdetails': '1',
            'namedetails': '1',
            'limit': '8',
            'countrycodes': 'eg',
            'accept-language': 'en',
          },
        );

        final response = await _client.get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'User-Agent':
                'GeoGuideApp/1.0 (student-project; contact: geoguide@example.com)',
          },
        ).timeout(_nominatimTimeout);

        if (kDebugMode) {
          debugPrint('[Nearby] nominatim status=${response.statusCode} query=$q');
        }

        if (response.statusCode == 429 || response.statusCode == 503) {
          _startNominatimCooldown();
          break;
        }

        if (response.statusCode != 200) continue;

        final decoded = jsonDecode(response.body);
        if (decoded is! List) continue;

        final category = _categoryFromQuery(q, categories);

        for (final raw in decoded) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);

          final place = NearbyPlace.fromNominatim(
            item: item,
            originLat: lat,
            originLng: lng,
            category: category,
          );

          if (place.name.trim().isEmpty) continue;
          if (place.lat == 0 || place.lng == 0) continue;
          if (place.distanceKm > 25.0) continue;

          final searchableText = [
            place.name,
            place.address,
            place.category,
            ...place.types,
          ].join(' ').toLowerCase();

          if (!_acceptByRequestedCategory(
            wantedCategories: categories.toSet(),
            placeCategory: place.category,
            searchableText: searchableText,
          )) {
            continue;
          }

          final key = _dedupeKey(place);
          if (seen.add(key)) collected.add(place);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Nearby] nominatim failed query=$q error=$e');
        }
        // Do not stop all Nominatim text search after one slow query.
        // Try the next text query, then Overpass will still run after this.
        continue;
      }
    }

    collected.sort((a, b) => _rankScore(b).compareTo(_rankScore(a)));
    if (kDebugMode) {
      debugPrint('[Nearby] nominatim total=${collected.length}');
    }
    return collected.take(limit).toList();
  }

  List<String> _buildNominatimQueries(
    String cityName,
    List<String> categories,
  ) {
    final city = cityName.trim().isEmpty ? 'Egypt' : '$cityName Egypt';
    final queries = <String>[];

    if (categories.contains('tourist')) {
      queries.addAll([
        'tourist attractions in $city',
        'museums in $city',
        'historic places in $city',
      ]);
    }

    if (categories.contains('outing')) {
      queries.addAll([
        'parks in $city',
        'gardens in $city',
        'malls in $city',
        'cinemas in $city',
        'zoos in $city',
        'aquariums in $city',
        'theme parks in $city',
        'outing places in $city',
      ]);
    }

    if (categories.contains('hotel')) {
      queries.add('hotels in $city');
    }

    if (categories.contains('restaurant')) {
      queries.add('restaurants in $city');
    }

    if (categories.contains('cafe')) {
      queries.addAll([
        'cafes in $city',
        'coffee shops in $city',
      ]);
    }

    return queries.toSet().toList();
  }

  String _categoryFromQuery(String query, List<String> fallbackCategories) {
    final q = query.toLowerCase();

    if (q.contains('hotel')) return 'hotel';
    if (q.contains('restaurant')) return 'restaurant';
    if (q.contains('cafe') || q.contains('coffee')) return 'cafe';

    if (q.contains('park') ||
        q.contains('garden') ||
        q.contains('mall') ||
        q.contains('cinema') ||
        q.contains('zoo') ||
        q.contains('aquarium') ||
        q.contains('theme') ||
        q.contains('outing')) {
      return 'outing';
    }

    if (q.contains('museum') ||
        q.contains('historic') ||
        q.contains('tourist') ||
        q.contains('attraction')) {
      return 'tourist';
    }

    return fallbackCategories.isNotEmpty ? fallbackCategories.first : 'tourist';
  }

  Future<List<NearbyPlace>> _fetchFromOverpassProgressive({
    required double lat,
    required double lng,
    required List<String> categories,
    required int limit,
  }) async {
    if (_isOverpassCoolingDown) {
      if (kDebugMode) {
        debugPrint('[Nearby] Overpass cooling down; skip live request.');
      }
      return const [];
    }

    // One radius per user action to avoid repeated Overpass timeouts.
    final radiusOptions = <int>[5000];

    final collected = <NearbyPlace>[];
    final seen = <String>{};

    for (final radius in radiusOptions) {
      final fresh = await _fetchFromOverpass(
        lat: lat,
        lng: lng,
        radiusMeters: radius,
        categories: categories,
        limit: math.max(limit, 40),
      );

      if (kDebugMode) {
        debugPrint(
          '[Nearby] radius=$radius found=${fresh.length} totalBefore=${collected.length}',
        );
      }

      for (final place in fresh) {
        if (place.distanceKm > 20.0) continue;
        final key = _dedupeKey(place);
        if (seen.add(key)) collected.add(place);
      }

      if (kDebugMode) {
        debugPrint('[Nearby] radius=$radius totalAfter=${collected.length}');
      }

      if (collected.length >= limit) break;
    }

    if (collected.isEmpty) {
      _startOverpassCooldown();
    }

    collected.sort((a, b) => _rankScore(b).compareTo(_rankScore(a)));
    return collected.take(limit).toList();
  }

  Future<List<NearbyPlace>> _fetchFromOverpass({
    required double lat,
    required double lng,
    required int radiusMeters,
    required List<String> categories,
    required int limit,
  }) async {
    if (_isOverpassCoolingDown) return const [];

    final queries = _buildOverpassQueries(
      lat: lat,
      lng: lng,
      radiusMeters: radiusMeters,
      categories: categories,
    );

    if (queries.isEmpty) return const [];

    final body = '''
[out:json][timeout:6];
(
${queries.join('\n')}
);
out center tags $limit;
''';

    final allResults = <NearbyPlace>[];
    final globalSeen = <String>{};
    int endpointFailures = 0;

    for (final endpoint in _overpassEndpoints.take(1)) {
      try {
        final res = await _client
            .post(
              Uri.parse(endpoint),
              headers: const {
                'Content-Type':
                    'application/x-www-form-urlencoded; charset=UTF-8',
                'Accept': 'application/json',
                'User-Agent':
                    'GeoGuideApp/1.0 (student-project; contact: geoguide@example.com)',
              },
              body: {'data': body},
            )
            .timeout(_overpassHttpTimeout);

        if (kDebugMode) {
          debugPrint('[Nearby] endpoint=$endpoint status=${res.statusCode}');
        }

        if (res.statusCode == 429 || res.statusCode == 504) {
          endpointFailures++;
          continue;
        }

        if (res.statusCode != 200) {
          endpointFailures++;
          continue;
        }

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final elements = data['elements'] as List? ?? const [];

        if (kDebugMode) {
          debugPrint('[Nearby] endpoint=$endpoint raw elements=${elements.length}');
        }

        int acceptedCount = 0;
        int rejectedCount = 0;
        int duplicateCount = 0;
        int unnamedCount = 0;
        int invalidLocationCount = 0;

        for (final raw in elements) {
          final element = Map<String, dynamic>.from(raw as Map);

          double itemLat = 0;
          double itemLng = 0;

          if (element['lat'] != null && element['lon'] != null) {
            itemLat = ((element['lat'] ?? 0) as num).toDouble();
            itemLng = ((element['lon'] ?? 0) as num).toDouble();
          } else if (element['center'] is Map) {
            final center = Map<String, dynamic>.from(element['center'] as Map);
            itemLat = ((center['lat'] ?? 0) as num).toDouble();
            itemLng = ((center['lon'] ?? 0) as num).toDouble();

            element['lat'] = itemLat;
            element['lon'] = itemLng;
          }

          if (itemLat == 0 || itemLng == 0) {
            invalidLocationCount++;
            continue;
          }

          final place = NearbyPlace.fromOsm(
            element: element,
            originLat: lat,
            originLng: lng,
          );

          if (place.name.trim().isEmpty) {
            unnamedCount++;
            continue;
          }

          if (place.distanceKm > 20.0) {
            rejectedCount++;
            continue;
          }

          final wantedCategories = categories.toSet();
          final placeCategory = NearbyPlace._normalizeCategory(place.category);

          final searchableText = [
            place.name,
            place.category,
            place.address,
            ...place.types,
          ].join(' ').toLowerCase();

          final accepted = _acceptByRequestedCategory(
            wantedCategories: wantedCategories,
            placeCategory: placeCategory,
            searchableText: searchableText,
          );

          if (!accepted) {
            rejectedCount++;
            continue;
          }

          final dedupeKey = _dedupeKey(place);
          if (!globalSeen.add(dedupeKey)) {
            duplicateCount++;
            continue;
          }

          acceptedCount++;
          allResults.add(place);
        }

        if (kDebugMode) {
          debugPrint(
            '[Nearby] accepted=$acceptedCount rejected=$rejectedCount '
            'duplicates=$duplicateCount unnamed=$unnamedCount '
            'invalidLocation=$invalidLocationCount total=${allResults.length}',
          );
        }

        if (allResults.isNotEmpty || elements.isNotEmpty) break;
      } catch (e) {
        endpointFailures++;
        if (kDebugMode) {
          debugPrint('[Nearby] endpoint failed=$endpoint error=$e');
        }
      }
    }

    if (allResults.isEmpty && endpointFailures >= 1) {
      if (kDebugMode) {
        debugPrint('[Nearby] Overpass attempt failed for this radius');
      }
    }

    allResults.sort((a, b) => _rankScore(b).compareTo(_rankScore(a)));

    if (kDebugMode) {
      debugPrint('[Nearby] final overpass results=${allResults.length}');
    }

    return allResults.take(limit).toList();
  }

  List<String> _buildOverpassQueries({
    required double lat,
    required double lng,
    required int radiusMeters,
    required List<String> categories,
  }) {
    final queries = <String>[];

    if (categories.contains('hotel')) {
      queries.add(
        'node["tourism"~"hotel|hostel|guest_house|motel|apartment|resort"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'way["tourism"~"hotel|hostel|guest_house|motel|apartment|resort"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'relation["tourism"~"hotel|hostel|guest_house|motel|apartment|resort"](around:$radiusMeters,$lat,$lng);',
      );
    }

    if (categories.contains('restaurant')) {
      queries.add(
        'node["amenity"~"restaurant|fast_food|food_court"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'way["amenity"~"restaurant|fast_food|food_court"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'relation["amenity"~"restaurant|fast_food|food_court"](around:$radiusMeters,$lat,$lng);',
      );
    }

    if (categories.contains('cafe')) {
      queries.add(
        'node["amenity"~"cafe|ice_cream"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'way["amenity"~"cafe|ice_cream"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'relation["amenity"~"cafe|ice_cream"](around:$radiusMeters,$lat,$lng);',
      );

      queries.add(
        'node["shop"~"coffee|bakery|pastry|confectionery"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'way["shop"~"coffee|bakery|pastry|confectionery"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'relation["shop"~"coffee|bakery|pastry|confectionery"](around:$radiusMeters,$lat,$lng);',
      );
    }

    if (categories.contains('tourist')) {
      queries.add(
        'node["tourism"~"museum|attraction|viewpoint|gallery"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'way["tourism"~"museum|attraction|viewpoint|gallery"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'relation["tourism"~"museum|attraction|viewpoint|gallery"](around:$radiusMeters,$lat,$lng);',
      );

      queries.add('node["historic"](around:$radiusMeters,$lat,$lng);');
      queries.add('way["historic"](around:$radiusMeters,$lat,$lng);');
      queries.add('relation["historic"](around:$radiusMeters,$lat,$lng);');
    }

    if (categories.contains('outing')) {
      queries.add(
        'node["leisure"~"park|garden|playground|beach_resort|sports_centre|fitness_centre"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'way["leisure"~"park|garden|playground|beach_resort|sports_centre|fitness_centre"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'relation["leisure"~"park|garden|playground|beach_resort|sports_centre|fitness_centre"](around:$radiusMeters,$lat,$lng);',
      );

      queries.add(
        'node["amenity"~"cinema|theatre|arts_centre|community_centre|fountain"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'way["amenity"~"cinema|theatre|arts_centre|community_centre|fountain"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'relation["amenity"~"cinema|theatre|arts_centre|community_centre|fountain"](around:$radiusMeters,$lat,$lng);',
      );

      queries.add(
        'node["shop"~"mall|department_store"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'way["shop"~"mall|department_store"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'relation["shop"~"mall|department_store"](around:$radiusMeters,$lat,$lng);',
      );

      queries.add(
        'node["tourism"~"theme_park|zoo|aquarium|picnic_site"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'way["tourism"~"theme_park|zoo|aquarium|picnic_site"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'relation["tourism"~"theme_park|zoo|aquarium|picnic_site"](around:$radiusMeters,$lat,$lng);',
      );
    }

    return queries;
  }

  List<NearbyPlace> mergeNearbyPlaces({
    required List<NearbyPlace> oldPlaces,
    required List<NearbyPlace> newPlaces,
    int limit = 24,
  }) {
    final result = <NearbyPlace>[];
    final seen = <String>{};

    for (final place in [...oldPlaces, ...newPlaces]) {
      final name = place.name.trim();
      if (name.isEmpty) continue;

      final key = _dedupeKey(place);
      if (seen.add(key)) result.add(place);
    }

    result.sort((a, b) => _rankScore(b).compareTo(_rankScore(a)));

    return result.take(limit).toList();
  }

  bool _acceptByRequestedCategory({
    required Set<String> wantedCategories,
    required String placeCategory,
    required String searchableText,
  }) {
    if (wantedCategories.length == 1) {
      final wanted = wantedCategories.first;

      switch (wanted) {
        case 'hotel':
          return _looksLikeHotel(placeCategory, searchableText);
        case 'restaurant':
          return _looksLikeRestaurant(placeCategory, searchableText);
        case 'cafe':
          return _looksLikeCafe(placeCategory, searchableText);
        case 'tourist':
          return _looksLikeTourist(placeCategory, searchableText);
        case 'outing':
          return _looksLikeOuting(placeCategory, searchableText);
        default:
          return wantedCategories.contains(placeCategory);
      }
    }

    if (wantedCategories.contains('hotel') &&
        _looksLikeHotel(placeCategory, searchableText)) return true;
    if (wantedCategories.contains('restaurant') &&
        _looksLikeRestaurant(placeCategory, searchableText)) return true;
    if (wantedCategories.contains('cafe') &&
        _looksLikeCafe(placeCategory, searchableText)) return true;
    if (wantedCategories.contains('tourist') &&
        _looksLikeTourist(placeCategory, searchableText)) return true;
    if (wantedCategories.contains('outing') &&
        _looksLikeOuting(placeCategory, searchableText)) return true;

    return false;
  }

  bool _looksLikeHotel(String placeCategory, String text) {
    return placeCategory == 'hotel' ||
        text.contains('tourism:hotel') ||
        text.contains('tourism:hostel') ||
        text.contains('tourism:guest_house') ||
        text.contains('tourism:motel') ||
        text.contains('tourism:apartment') ||
        text.contains('tourism:resort') ||
        text.contains('hotel') ||
        text.contains('hostel') ||
        text.contains('resort') ||
        text.contains('guest house') ||
        text.contains('guest_house') ||
        text.contains('فندق') ||
        text.contains('منتجع') ||
        text.contains('نزل');
  }

  bool _looksLikeRestaurant(String placeCategory, String text) {
    return placeCategory == 'restaurant' ||
        text.contains('amenity:restaurant') ||
        text.contains('amenity:fast_food') ||
        text.contains('amenity:food_court') ||
        text.contains('restaurant') ||
        text.contains('fast_food') ||
        text.contains('food court') ||
        text.contains('food_court') ||
        text.contains('مطعم');
  }

  bool _looksLikeCafe(String placeCategory, String text) {
    return placeCategory == 'cafe' ||
        text.contains('amenity:cafe') ||
        text.contains('amenity:ice_cream') ||
        text.contains('shop:coffee') ||
        text.contains('shop:bakery') ||
        text.contains('shop:pastry') ||
        text.contains('shop:confectionery') ||
        text.contains('cuisine:coffee') ||
        text.contains('cuisine:dessert') ||
        text.contains('cafe') ||
        text.contains('café') ||
        text.contains('coffee') ||
        text.contains('bakery') ||
        text.contains('pastry') ||
        text.contains('dessert') ||
        text.contains('ice_cream') ||
        text.contains('ice cream') ||
        text.contains('كافيه') ||
        text.contains('مقهى') ||
        text.contains('قهوة') ||
        text.contains('حلويات');
  }

  bool _looksLikeTourist(String placeCategory, String text) {
    return placeCategory == 'tourist' ||
        text.contains('tourism:museum') ||
        text.contains('tourism:attraction') ||
        text.contains('tourism:viewpoint') ||
        text.contains('tourism:gallery') ||
        text.contains('historic:') ||
        text.contains('museum') ||
        text.contains('attraction') ||
        text.contains('viewpoint') ||
        text.contains('gallery') ||
        text.contains('historic') ||
        text.contains('monument') ||
        text.contains('archaeological') ||
        text.contains('متحف') ||
        text.contains('أثري') ||
        text.contains('اثري') ||
        text.contains('معلم');
  }

  bool _looksLikeOuting(String placeCategory, String text) {
    return placeCategory == 'outing' ||
        text.contains('leisure:park') ||
        text.contains('leisure:garden') ||
        text.contains('leisure:playground') ||
        text.contains('amenity:cinema') ||
        text.contains('amenity:theatre') ||
        text.contains('shop:mall') ||
        text.contains('tourism:zoo') ||
        text.contains('tourism:aquarium') ||
        text.contains('tourism:theme_park') ||
        text.contains('park') ||
        text.contains('garden') ||
        text.contains('mall') ||
        text.contains('cinema') ||
        text.contains('theatre') ||
        text.contains('zoo') ||
        text.contains('aquarium') ||
        text.contains('theme park') ||
        text.contains('amusement') ||
        text.contains('حديقة') ||
        text.contains('مول') ||
        text.contains('سينما') ||
        text.contains('خروجة') ||
        text.contains('خروجات');
  }

  static bool get _isOverpassCoolingDown {
    final until = _overpassCooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  static bool get _isNominatimCoolingDown {
    final until = _nominatimCooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  static void _startOverpassCooldown() {
    _overpassCooldownUntil = DateTime.now().add(_cooldownDuration);
    if (kDebugMode) {
      debugPrint(
        '[Nearby] Overpass unavailable; cooling down live reload for '
        '${_cooldownDuration.inSeconds}s',
      );
    }
  }

  static void _startNominatimCooldown() {
    _nominatimCooldownUntil = DateTime.now().add(_cooldownDuration);
    if (kDebugMode) {
      debugPrint(
        '[Nearby] Nominatim unavailable; cooling down text search for '
        '${_cooldownDuration.inSeconds}s',
      );
    }
  }

  static String _dedupeKey(NearbyPlace place) {
    final cleanName = _normalizeText(place.name);
    final category = NearbyPlace._normalizeCategory(place.category);
    return '$cleanName|$category';
  }

  static String _normalizeText(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[\u064B-\u065F]'), '')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double _rankScore(NearbyPlace place) {
    double score = 0;

    if (place.distanceKm > 0 && place.distanceKm < 999) {
      score += math.max(0, 40 - place.distanceKm);
    }

    if (place.rating > 0) score += place.rating * 5;
    if (place.userRatingsTotal > 0) {
      score += math.min(12, math.log(place.userRatingsTotal + 1));
    }

    if (place.hasOpeningHours) score += 2;
    if (place.isOpenNow) score += 4;
    if (place.website != null && place.website!.isNotEmpty) score += 2;
    if (place.wikipediaUrl != null && place.wikipediaUrl!.isNotEmpty) score += 3;

    final name = place.name.toLowerCase();

    const famousWords = [
      'museum',
      'tower',
      'opera',
      'palace',
      'citadel',
      'park',
      'garden',
      'mall',
      'zoo',
      'aquarium',
      'cinema',
      'theatre',
      'theme',
      'متحف',
      'برج',
      'قصر',
      'قلعة',
      'حديقة',
      'مول',
      'سينما',
    ];

    for (final word in famousWords) {
      if (name.contains(word)) {
        score += 4;
        break;
      }
    }

    return score;
  }
}
