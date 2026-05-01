// ============================================================
//  services/nearby-service.dart
//  FINAL FULL VERSION — preserved API + Overpass fixes
//
//  Fixes:
//  - Keeps full NearbyPlace model and all methods.
//  - Uses meaningful User-Agent to avoid 429.
//  - Sends Overpass request as form-urlencoded.
//  - Uses fallback Overpass endpoints.
//  - Uses progressive radius to avoid heavy requests.
//  - Uses out center; and supports node/way/relation.
//  - Category-aware search radius to avoid Cairo overload/429.
//- Strict cafe matching so restaurant noise does not appear as cafes.
// ============================================================

import 'dart:convert';
import 'dart:math' as math;

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

  factory NearbyPlace.fromOsm({
    required Map<String, dynamic> element,
    required double originLat,
    required double originLng,
  }) {
    final tags = Map<String, dynamic>.from(element['tags'] as Map? ?? {});
    final lat = ((element['lat'] ?? 0) as num).toDouble();
    final lng = ((element['lon'] ?? 0) as num).toDouble();

    final category = _detectCategory(tags);
    final address = _buildAddress(tags);
    final website = _extractWebsite(tags);

final type = (element['type'] ?? 'osm').toString();
final osmId = (element['id'] ?? '').toString();
    return NearbyPlace(
      placeId: '${type}_$osmId',
      name: (tags['name'] ?? tags['name:en'] ?? '').toString().trim(),
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
        cat.contains('motel') ||
        cat.contains('resort') ||
        cat.contains('apartment')) {
      return 'hotel';
    }

    if (cat.contains('restaurant') ||
        cat.contains('fast_food') ||
        cat.contains('food_court')) {
      return 'restaurant';
    }

    if (cat.contains('cafe') || cat.contains('coffee')) return 'cafe';

    if (cat.contains('outing') ||
        cat.contains('park') ||
        cat.contains('garden') ||
        cat.contains('mall') ||
        cat.contains('cinema') ||
        cat.contains('beach') ||
        cat.contains('leisure')) {
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
        tourism == 'apartment') {
      return 'hotel';
    }

    // Keep cafe detection before restaurant because many dessert/coffee places
    // are tagged as shops, not only amenity=cafe.
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
        shop == 'mall' ||
        shop == 'department_store') {
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

  // Session cache prevents repeated Overpass calls for the same location/category.
  static final Map<String, List<NearbyPlace>> _nearbyMemoryCache = {};

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
      if (place.fetchedAt == null) continue;
      if (latest == null || place.fetchedAt!.isAfter(latest)) {
        latest = place.fetchedAt!;
      }
    }
    return latest;
  }

  Future<List<NearbyPlace>> getNearbyForCoordinates({
    required double lat,
    required double lng,
    List<String> categories = const [
      'hotel',
      'restaurant',
      'cafe',
      'tourist',
      'outing',
    ],
    int limit = 36,
  }) async {
    if (lat == 0 || lng == 0) return [];

    final normalizedCategories = categories
        .map((e) => NearbyPlace._normalizeCategory(e))
        .toSet()
        .toList();

    final cacheKey = '${lat.toStringAsFixed(4)}|${lng.toStringAsFixed(4)}|${normalizedCategories.join(',')}|$limit';
    final cachedNearby = _nearbyMemoryCache[cacheKey];
    if (cachedNearby != null && cachedNearby.isNotEmpty) {
      return cachedNearby.take(limit).toList();
    }

    // Category-aware progressive widening.
    // Cairo/Giza cafes can return thousands of elements, so cafes use smaller
    // radii to avoid Overpass 429/timeouts and noisy results.
    final onlyCafe = normalizedCategories.length == 1 &&
        normalizedCategories.contains('cafe');
    final onlyFood = normalizedCategories.every(
      (c) => c == 'cafe' || c == 'restaurant',
    );

    final radiusOptions = onlyCafe
        ? <int>[2500, 5000, 8000, 12000]
        : onlyFood
            ? <int>[3000, 7000, 12000, 18000]
            : <int>[3000, 7000, 12000, 20000, 30000];

    final collected = <NearbyPlace>[];
    final seen = <String>{};

    for (final radius in radiusOptions) {
      final fresh = await _fetchFromOverpass(
        lat: lat,
        lng: lng,
        radiusMeters: radius,
        categories: normalizedCategories,
        limit: math.max(limit, 80),
      );

      print('[Nearby] radius=$radius found=${fresh.length} totalBefore=${collected.length}');

      for (final place in fresh) {
        if (place.distanceKm > 30.0) continue;
        final key = _dedupeKey(place);
        if (seen.add(key)) collected.add(place);
      }

      print('[Nearby] radius=$radius totalAfter=${collected.length}');

      // Stop only after a meaningful radius, not from the first 3km scan.
      if (collected.length >= limit && radius >= 12000) break;
    }

    collected.sort((a, b) => _rankScore(b).compareTo(_rankScore(a)));
    final finalNearby = collected.take(limit).toList();
    if (finalNearby.isNotEmpty) _nearbyMemoryCache[cacheKey] = finalNearby;
    return finalNearby;
  }

  Future<List<NearbyPlace>> _fetchFromOverpass({
    required double lat,
    required double lng,
    required int radiusMeters,
    required List<String> categories,
    required int limit,
  }) async {
    final queries = <String>[];

    if (categories.contains('hotel')) {
      queries.add(
        'node["tourism"~"hotel|hostel|guest_house|motel|apartment"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'way["tourism"~"hotel|hostel|guest_house|motel|apartment"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'relation["tourism"~"hotel|hostel|guest_house|motel|apartment"](around:$radiusMeters,$lat,$lng);',
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
      // Keep cafe queries strict. Do NOT include restaurant/fast_food here,
      // otherwise cafe search will show many restaurants with names that do
      // not look like cafes.
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

      queries.add(
        'node["cuisine"~"coffee|dessert|cake|pastry|ice_cream"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'way["cuisine"~"coffee|dessert|cake|pastry|ice_cream"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'relation["cuisine"~"coffee|dessert|cake|pastry|ice_cream"](around:$radiusMeters,$lat,$lng);',
      );
    }


    if (categories.contains('tourist')) {
      queries.add(
        'node["tourism"~"museum|attraction|viewpoint|gallery"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add('node["historic"](around:$radiusMeters,$lat,$lng);');

      queries.add(
        'way["tourism"~"museum|attraction|viewpoint|gallery"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add('way["historic"](around:$radiusMeters,$lat,$lng);');

      queries.add(
        'relation["tourism"~"museum|attraction|viewpoint|gallery"](around:$radiusMeters,$lat,$lng);',
      );
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
        'node["shop"~"mall|department_store|supermarket"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'way["shop"~"mall|department_store|supermarket"](around:$radiusMeters,$lat,$lng);',
      );
      queries.add(
        'relation["shop"~"mall|department_store|supermarket"](around:$radiusMeters,$lat,$lng);',
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

    if (queries.isEmpty) return [];

    final body = '''
[out:json][timeout:14];
(
${queries.join('\n')}
);
out center;
''';

    final allResults = <NearbyPlace>[];
    final globalSeen = <String>{};

    for (final endpoint in _overpassEndpoints) {
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
            .timeout(const Duration(seconds: 10));

        print('[Nearby] endpoint=$endpoint status=${res.statusCode}');

        if (res.statusCode != 200) continue;

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final elements = (data['elements'] as List? ?? const []);

        print('[Nearby] endpoint=$endpoint raw elements=${elements.length}');

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
          if (place.distanceKm > 30.0) continue;

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

        print(
          '[Nearby] accepted=$acceptedCount rejected=$rejectedCount '
          'duplicates=$duplicateCount unnamed=$unnamedCount '
          'invalidLocation=$invalidLocationCount total=${allResults.length}',
        );

        // One good endpoint is enough. Querying all mirrors after a successful
        // response causes delays and 429s, especially in Cairo.
        if (allResults.length >= limit) break;
      } catch (e) {
        print('[Nearby] endpoint failed=$endpoint error=$e');
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }

    allResults.sort((a, b) => _rankScore(b).compareTo(_rankScore(a)));
    print('[Nearby] final from all endpoints=${allResults.length}');
    return allResults.take(limit).toList();
  }

  Future<NearbyUpdateResult> getNearbyWithAutoRefresh({
    required double lat,
    required double lng,
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

    if (!needsRefresh && existingPlaces.isNotEmpty) {
      final sorted = [...existingPlaces]
        ..sort((a, b) => _rankScore(b).compareTo(_rankScore(a)));

      return NearbyUpdateResult(
        places: sorted.take(limit).toList(),
        didRefresh: false,
        refreshedAt: latest ?? DateTime.now(),
      );
    }

    final fresh = await getNearbyForCoordinates(
      lat: lat,
      lng: lng,
      categories: categories,
      limit: math.max(limit, 40),
    );

    if (fresh.isEmpty && existingPlaces.isNotEmpty) {
      final sorted = [...existingPlaces]
        ..sort((a, b) => _rankScore(b).compareTo(_rankScore(a)));

      return NearbyUpdateResult(
        places: sorted.take(limit).toList(),
        didRefresh: false,
        refreshedAt: latest ?? DateTime.now(),
      );
    }

    final merged = mergeNearbyPlaces(
      oldPlaces: existingPlaces,
      newPlaces: fresh,
      limit: limit,
    );

    return NearbyUpdateResult(
      places: merged,
      didRefresh: true,
      refreshedAt: DateTime.now(),
    );
  }

  bool _acceptByRequestedCategory({
    required Set<String> wantedCategories,
    required String placeCategory,
    required String searchableText,
  }) {
    // Single-category searches must stay strict so each tab/search returns
    // only the requested bucket, not visually unrelated places.
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

    // Multi-category mode, such as Place Info nearby tab, can include several
    // buckets, but each accepted item must still match one of them accurately.
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
    // Do not accept cafes in restaurant-only mode unless OSM explicitly tags it
    // as restaurant/fast_food/food_court.
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
    // Keep cafe strict. No generic restaurant/fast_food here.
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
        text.contains('archaeological') ||
        text.contains('monument') ||
        text.contains('memorial') ||
        text.contains('castle') ||
        text.contains('fort') ||
        text.contains('citadel') ||
        text.contains('متحف') ||
        text.contains('معلم') ||
        text.contains('أثر') ||
        text.contains('اثار') ||
        text.contains('آثار') ||
        text.contains('قلعة');
  }

  bool _looksLikeOuting(String placeCategory, String text) {
    return placeCategory == 'outing' ||
        text.contains('leisure:park') ||
        text.contains('leisure:garden') ||
        text.contains('leisure:playground') ||
        text.contains('leisure:beach_resort') ||
        text.contains('leisure:sports_centre') ||
        text.contains('amenity:cinema') ||
        text.contains('amenity:theatre') ||
        text.contains('amenity:arts_centre') ||
        text.contains('shop:mall') ||
        text.contains('tourism:theme_park') ||
        text.contains('tourism:zoo') ||
        text.contains('tourism:aquarium') ||
        text.contains('park') ||
        text.contains('garden') ||
        text.contains('playground') ||
        text.contains('cinema') ||
        text.contains('theatre') ||
        text.contains('theater') ||
        text.contains('mall') ||
        text.contains('zoo') ||
        text.contains('aquarium') ||
        text.contains('beach') ||
        text.contains('حديقة') ||
        text.contains('سينما') ||
        text.contains('مول') ||
        text.contains('شاطئ') ||
        text.contains('ملاهي');
  }

  List<NearbyPlace> mergeNearbyPlaces({
    required List<NearbyPlace> oldPlaces,
    required List<NearbyPlace> newPlaces,
    int limit = 24,
  }) {
    final map = <String, NearbyPlace>{};

    for (final place in oldPlaces) {
      map[_dedupeKey(place)] = place;
    }

    for (final place in newPlaces) {
      final key = _dedupeKey(place);
      if (!map.containsKey(key)) {
        map[key] = place;
        continue;
      }

      final existing = map[key]!;
      map[key] = _pickBetterPlace(existing, place);
    }

    final merged = map.values.toList()
      ..sort((a, b) => _rankScore(b).compareTo(_rankScore(a)));

    return merged.take(limit).toList();
  }

  NearbyPlace _pickBetterPlace(NearbyPlace oldPlace, NearbyPlace newPlace) {
    final oldScore = _completenessScore(oldPlace);
    final newScore = _completenessScore(newPlace);

    if (newScore >= oldScore) {
      return newPlace.copyWith(
        fetchedAt: newPlace.fetchedAt ?? DateTime.now(),
      );
    }

    return oldPlace.copyWith(
      fetchedAt: newPlace.fetchedAt ?? oldPlace.fetchedAt ?? DateTime.now(),
    );
  }

  double _completenessScore(NearbyPlace place) {
    double score = 0;

    if (place.name.trim().isNotEmpty) score += 4;
    if (place.address.trim().isNotEmpty) score += 3;
    if (place.website != null && place.website!.trim().isNotEmpty) score += 2;
    if (place.bookingUrl != null && place.bookingUrl!.trim().isNotEmpty) {
      score += 2;
    }
    if (place.wikipediaUrl != null && place.wikipediaUrl!.trim().isNotEmpty) {
      score += 1.5;
    }
    if (place.phone != null && place.phone!.trim().isNotEmpty) score += 1;
    if (place.hasOpeningHours) score += 1;
    if (place.imageUrl.trim().isNotEmpty) score += 1;
    if (place.rating > 0) score += place.rating / 2;
    if (place.userRatingsTotal > 0) score += 1;

    return score;
  }

  String _dedupeKey(NearbyPlace place) {
    return '${place.name.trim().toLowerCase()}|'
        '${NearbyPlace._normalizeCategory(place.category)}|'
        '${place.lat.toStringAsFixed(4)}|${place.lng.toStringAsFixed(4)}';
  }

  double _rankScore(NearbyPlace place) {
    double score = 100 - place.distanceKm;
    score += _completenessScore(place);

    final cat = NearbyPlace._normalizeCategory(place.category);
    final text = [place.name, place.category, ...place.types].join(' ').toLowerCase();
    if (cat == 'hotel') score += 2;
    if (cat == 'restaurant') score += 2;
    if (cat == 'cafe') score += 3.5;
    if (text.contains('cafe') ||
        text.contains('coffee') ||
        text.contains('كافيه') ||
        text.contains('مقهى')) score += 3;
    if (cat == 'tourist') score += 3;
    if (cat == 'outing') score += 2.5;

    return score;
  }
}
