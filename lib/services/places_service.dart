// ============================================================
//  services/places_service.dart  (REBUILT)
//
//  Source of curated place data per city.
//  Uses PlaceCategoryNormalizer for all category handling.
// ============================================================

// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/services/image-service.dart';
import 'package:http/http.dart' as http;
import 'package:geoguide/core/place_category_normalizer.dart';
import 'package:geoguide/models.dart/landmark_model.dart';

class GooglePlacesService {
  GooglePlacesService({
    ImageService? imageService,
    FirebaseService? firebase,
  })  : _imageService = imageService ?? ImageService(),
        _firebase = firebase ?? FirebaseService();

  final ImageService _imageService;
  final FirebaseService _firebase;

  // ── Curated landmark data per city ────────────────────────
  static const Map<String, List<Map<String, dynamic>>> _cityLandmarks = {
    'cairo': [
      {
        'name': 'Egyptian Museum',
        'lat': 30.0478,
        'lng': 31.2336,
        'category': 'tourist',
        'address': 'Tahrir Square, Cairo'
      },
      {
        'name': 'Cairo Tower',
        'lat': 30.0459,
        'lng': 31.2243,
        'category': 'tourist',
        'address': 'Gezira Island, Cairo'
      },
      {
        'name': 'Khan el-Khalili',
        'lat': 30.0477,
        'lng': 31.2625,
        'category': 'tourist',
        'address': 'Islamic Cairo'
      },
      {
        'name': 'Al-Azhar Mosque',
        'lat': 30.0459,
        'lng': 31.2618,
        'category': 'tourist',
        'address': 'Al-Azhar, Cairo'
      },
      {
        'name': 'Citadel of Cairo',
        'lat': 30.0286,
        'lng': 31.2599,
        'category': 'tourist',
        'address': 'Salah Salem, Cairo'
      },
      {
        'name': 'Cairo Opera House',
        'lat': 30.0407,
        'lng': 31.2244,
        'category': 'tourist',
        'address': 'Gezira Island, Cairo'
      },
      {
        'name': 'Al-Muizz Street',
        'lat': 30.0534,
        'lng': 31.2614,
        'category': 'tourist',
        'address': 'Islamic Cairo'
      },
      {
        'name': 'Coptic Cairo',
        'lat': 30.0051,
        'lng': 31.2296,
        'category': 'tourist',
        'address': 'Old Cairo'
      },
      {
        'name': 'Abdeen Palace',
        'lat': 30.0433,
        'lng': 31.2480,
        'category': 'tourist',
        'address': 'Downtown Cairo'
      },
      {
        'name': 'Cairo Zoo',
        'lat': 30.0149,
        'lng': 31.2089,
        'category': 'outing',
        'address': 'Giza, Cairo'
      },
      {
        'name': 'Koshary El Tahrir',
        'lat': 30.0444,
        'lng': 31.2357,
        'category': 'restaurant',
        'address': 'Tahrir Square'
      },
      {
        'name': 'Naguib Mahfouz Cafe',
        'lat': 30.0477,
        'lng': 31.2627,
        'category': 'cafe',
        'address': 'Khan el-Khalili'
      },
      {
        'name': 'Andrea Restaurant',
        'lat': 30.0196,
        'lng': 31.2124,
        'category': 'restaurant',
        'address': 'Mariotteyya, Cairo'
      },
    ],
    'giza': [
      {
        'name': 'Great Pyramid of Giza',
        'lat': 29.9792,
        'lng': 31.1342,
        'category': 'tourist',
        'address': 'Giza Plateau'
      },
      {
        'name': 'Great Sphinx of Giza',
        'lat': 29.9753,
        'lng': 31.1376,
        'category': 'tourist',
        'address': 'Giza Plateau'
      },
      {
        'name': 'Pyramid of Khafre',
        'lat': 29.9761,
        'lng': 31.1308,
        'category': 'tourist',
        'address': 'Giza Plateau'
      },
      {
        'name': 'Pyramid of Menkaure',
        'lat': 29.9727,
        'lng': 31.1283,
        'category': 'tourist',
        'address': 'Giza Plateau'
      },
      {
        'name': 'Solar Boat Museum',
        'lat': 29.9784,
        'lng': 31.1340,
        'category': 'tourist',
        'address': 'Giza Plateau'
      },
      {
        'name': 'Grand Egyptian Museum',
        'lat': 29.9880,
        'lng': 31.1162,
        'category': 'tourist',
        'address': 'Giza, Egypt'
      },
    ],
    'luxor': [
      {
        'name': 'Luxor Temple',
        'lat': 25.6994,
        'lng': 32.6392,
        'category': 'tourist',
        'address': 'Luxor City'
      },
      {
        'name': 'Karnak Temple',
        'lat': 25.7188,
        'lng': 32.6573,
        'category': 'tourist',
        'address': 'Karnak, Luxor'
      },
      {
        'name': 'Valley of the Kings',
        'lat': 25.7402,
        'lng': 32.6014,
        'category': 'tourist',
        'address': 'West Bank, Luxor'
      },
      {
        'name': 'Hatshepsut Temple',
        'lat': 25.7379,
        'lng': 32.6068,
        'category': 'tourist',
        'address': 'Deir el-Bahari, Luxor'
      },
      {
        'name': 'Colossi of Memnon',
        'lat': 25.7206,
        'lng': 32.6104,
        'category': 'tourist',
        'address': 'West Bank, Luxor'
      },
      {
        'name': 'Luxor Museum',
        'lat': 25.7015,
        'lng': 32.6415,
        'category': 'tourist',
        'address': 'Corniche el-Nile, Luxor'
      },
      {
        'name': 'Luxor Souk',
        'lat': 25.6993,
        'lng': 32.6400,
        'category': 'outing',
        'address': 'Luxor City Center'
      },
    ],
    'aswan': [
      {
        'name': 'Abu Simbel Temples',
        'lat': 22.3372,
        'lng': 31.6258,
        'category': 'tourist',
        'address': 'Abu Simbel, Aswan'
      },
      {
        'name': 'Philae Temple',
        'lat': 24.0234,
        'lng': 32.8840,
        'category': 'tourist',
        'address': 'Agilkia Island, Aswan'
      },
      {
        'name': 'Aswan High Dam',
        'lat': 23.9697,
        'lng': 32.8776,
        'category': 'tourist',
        'address': 'Aswan'
      },
      {
        'name': 'Nubian Museum',
        'lat': 24.0672,
        'lng': 32.8990,
        'category': 'tourist',
        'address': 'Aswan City'
      },
      {
        'name': 'Kom Ombo Temple',
        'lat': 24.4519,
        'lng': 32.9285,
        'category': 'tourist',
        'address': 'Kom Ombo, Aswan'
      },
      {
        'name': 'Elephantine Island',
        'lat': 24.0854,
        'lng': 32.8867,
        'category': 'tourist',
        'address': 'Aswan'
      },
      {
        'name': 'Aswan Botanical Garden',
        'lat': 24.0895,
        'lng': 32.8787,
        'category': 'outing',
        'address': 'Kitchener Island, Aswan'
      },
    ],
    'alexandria': [
      {
        'name': 'Bibliotheca Alexandrina',
        'lat': 31.2089,
        'lng': 29.9092,
        'category': 'tourist',
        'address': 'Corniche, Alexandria'
      },
      {
        'name': 'Citadel of Qaitbay',
        'lat': 31.2138,
        'lng': 29.8854,
        'category': 'tourist',
        'address': 'Eastern Harbor, Alexandria'
      },
      {
        'name': 'Pompey Pillar',
        'lat': 31.1841,
        'lng': 29.9063,
        'category': 'tourist',
        'address': 'Karmouz, Alexandria'
      },
      {
        'name': 'Alexandria National Museum',
        'lat': 31.1999,
        'lng': 29.9054,
        'category': 'tourist',
        'address': 'Al Horeyya Rd, Alexandria'
      },
      {
        'name': 'Montaza Palace',
        'lat': 31.2878,
        'lng': 30.0163,
        'category': 'tourist',
        'address': 'Montaza, Alexandria'
      },
      {
        'name': 'Stanley Bridge',
        'lat': 31.2438,
        'lng': 29.9623,
        'category': 'outing',
        'address': 'Stanley, Alexandria'
      },
      {
        'name': 'Kadoura Restaurant',
        'lat': 31.2136,
        'lng': 29.8958,
        'category': 'restaurant',
        'address': 'Bahr Side, Alexandria'
      },
    ],
    'sharm el sheikh': [
      {
        'name': 'Ras Mohammed National Park',
        'lat': 27.7326,
        'lng': 34.2448,
        'category': 'tourist',
        'address': 'South Sinai'
      },
      {
        'name': 'Naama Bay',
        'lat': 27.9119,
        'lng': 34.3298,
        'category': 'outing',
        'address': 'Sharm el-Sheikh'
      },
      {
        'name': 'Sharm Old Market',
        'lat': 27.8605,
        'lng': 34.2946,
        'category': 'outing',
        'address': 'Old Town, Sharm el-Sheikh'
      },
    ],
    'hurghada': [
      {
        'name': 'Giftun Island',
        'lat': 27.1667,
        'lng': 33.8833,
        'category': 'tourist',
        'address': 'Red Sea, Hurghada'
      },
      {
        'name': 'Hurghada Marina',
        'lat': 27.2166,
        'lng': 33.8345,
        'category': 'outing',
        'address': 'Hurghada'
      },
      {
        'name': 'Grand Aquarium',
        'lat': 27.1843,
        'lng': 33.8474,
        'category': 'tourist',
        'address': 'Hurghada'
      },
      {
        'name': 'Senzo Mall',
        'lat': 27.2421,
        'lng': 33.8322,
        'category': 'outing',
        'address': 'Hurghada'
      },
    ],
    'dahab': [
      {
        'name': 'Blue Hole Dahab',
        'lat': 28.5712,
        'lng': 34.5381,
        'category': 'tourist',
        'address': 'Dahab, South Sinai'
      },
      {
        'name': 'Dahab Lagoon',
        'lat': 28.4897,
        'lng': 34.5093,
        'category': 'outing',
        'address': 'Dahab'
      },
    ],
    'siwa': [
      {
        'name': 'Siwa Oasis',
        'lat': 29.2032,
        'lng': 25.5197,
        'category': 'tourist',
        'address': 'Siwa, Egypt'
      },
      {
        'name': 'Oracle Temple',
        'lat': 29.2068,
        'lng': 25.5174,
        'category': 'tourist',
        'address': 'Siwa'
      },
    ],
  };

  // ── Fetch all categories for a city ───────────────────────
  Future<List<Map<String, dynamic>>> fetchAllCategoriesForCity({
    required double lat,
    required double lng,
    required String cityId,
    required String cityName,
  }) async {
    final key = cityName.toLowerCase().trim();

    List<Map<String, dynamic>>? landmarks;
    for (final entry in _cityLandmarks.entries) {
      if (key.contains(entry.key) || entry.key.contains(key)) {
        landmarks = entry.value;
        break;
      }
    }

    if (landmarks == null) {
      // Fallback: fetch from Wikipedia search
      final wiki = await _fetchFromWikipedia(cityName, lat, lng);
      return wiki
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => PlaceCategoryNormalizer.isAllowed(
              (e['category'] ?? '').toString()))
          .toList();
    }

    return landmarks
        .map((lm) {
          final map = Map<String, dynamic>.from(lm);
          map['category'] = PlaceCategoryNormalizer.normalize(
            (map['category'] ?? 'tourist').toString(),
          );
          return map;
        })
        .where((e) => PlaceCategoryNormalizer.isAllowed(
            (e['category'] ?? '').toString()))
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchFromWikipedia(
    String cityName,
    double lat,
    double lng,
  ) async {
    try {
      final query = Uri.encodeComponent(
          'tourist attractions $cityName Egypt');
      final url = Uri.parse(
        'https://en.wikipedia.org/w/api.php'
        '?action=query&list=search&srsearch=$query'
        '&srlimit=10&format=json&origin=*',
      );

      final response =
          await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (data['query']?['search'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      final seen = <String>{};
      final mapped = <Map<String, dynamic>>[];

      for (final r in results) {
        final name = (r['title'] as String? ?? '').trim();
        if (name.isEmpty || !seen.add(name.toLowerCase())) continue;

        mapped.add({
          'name': name,
          'lat': lat,
          'lng': lng,
          'category': 'tourist',
          'address': cityName,
        });
      }

      return mapped;
    } catch (_) {
      return [];
    }
  }

  // ── Build Landmark from raw map (async — fetches images) ──
  Future<Landmark> fromGoogleResultAsync(
    Map<String, dynamic> place, {
    required String cityId,
    required String cityName,
  }) async {
    final name = (place['name'] as String? ?? '').trim();
    final lat = ((place['lat'] ?? 0) as num).toDouble();
    final lng = ((place['lng'] ?? 0) as num).toDouble();
    final category = PlaceCategoryNormalizer.normalize(
      (place['category'] as String? ?? 'tourist').trim(),
      contextText: name,
    );
    final address = (place['address'] as String? ?? cityName).trim();

    final mediaRaw = await _imageService.fetchImages(
      name,
      cityName: cityName,
      category: category,
      count: 7,
    );
    final metaBase =
        '$name $cityName ${PlaceCategoryNormalizer.normalize(category, contextText: name)}';
    final mediaUrls = await _imageService.filterPersistableImageUrls(
      urls: mediaRaw,
      placeName: name,
      cityName: cityName,
      category: category,
      metaTextBase: metaBase,
      findOwnersForImageUrl: _firebase.findLandmarkIdsWithImageUrl,
      excludeLandmarkId: null,
      maxCount: 7,
    );

    final imageUrl = mediaUrls.isNotEmpty ? mediaUrls.first : '';

    return Landmark(
      id: '',
      name: name,
      cityId: cityId,
      city: cityName,
      category: category,
      description: address,
      shortDescription: address,
      fullDescription: '',
      history: '',
      imageUrl: imageUrl,
      mediaUrls: mediaUrls,
      lat: lat,
      lng: lng,
      address: address,
      rating: 0,
      openingHours: '',
      location: '$lat, $lng',
      imagesRefreshedAt: mediaUrls.isNotEmpty ? DateTime.now() : null,
      sources: const {
        'base': 'curated_or_wikipedia',
        'images': 'image_service',
      },
    );
  }

  // ── Build Landmark from raw map (sync — no image fetch) ───
  Landmark fromGoogleResult(
    Map<String, dynamic> place, {
    required String cityId,
    required String cityName,
  }) {
    final name = (place['name'] as String? ?? '').trim();
    final lat = ((place['lat'] ?? 0) as num).toDouble();
    final lng = ((place['lng'] ?? 0) as num).toDouble();
    final category = PlaceCategoryNormalizer.normalize(
      (place['category'] as String? ?? 'tourist').trim(),
      contextText: name,
    );
    final address = (place['address'] as String? ?? cityName).trim();

    return Landmark(
      id: '',
      name: name,
      cityId: cityId,
      city: cityName,
      category: category,
      description: address,
      shortDescription: address,
      fullDescription: '',
      history: '',
      imageUrl: '',
      mediaUrls: const [],
      lat: lat,
      lng: lng,
      address: address,
      rating: 0,
      openingHours: '',
      location: '$lat, $lng',
      sources: const {
        'base': 'curated_or_wikipedia',
        'images': 'none',
      },
    );
  }

  // ── Save landmarks that don't exist yet ───────────────────
  Future<int> fetchAndSaveLandmarks({
    required String cityId,
    required String cityName,
  }) async {
    int savedCount = 0;

    try {
      final key = cityName.toLowerCase().trim();
      List<Map<String, dynamic>>? landmarks;

      for (final entry in _cityLandmarks.entries) {
        if (key.contains(entry.key) || entry.key.contains(key)) {
          landmarks = entry.value;
          break;
        }
      }

      if (landmarks == null) return 0;

      for (final place in landmarks) {
        final category = PlaceCategoryNormalizer.normalize(
          (place['category'] ?? 'tourist').toString(),
        );

        if (!PlaceCategoryNormalizer.isAllowed(category)) continue;

        await _savePlaceToFirestore(
          place: {...place, 'category': category},
          cityId: cityId,
          cityName: cityName,
        );
        savedCount++;
      }
    } catch (_) {}

    return savedCount;
  }

  Future<void> _savePlaceToFirestore({
    required Map<String, dynamic> place,
    required String cityId,
    required String cityName,
  }) async {
    final name = (place['name'] as String? ?? '').trim();
    final lat = ((place['lat'] ?? 0) as num).toDouble();
    final lng = ((place['lng'] ?? 0) as num).toDouble();
    final address = (place['address'] as String? ?? cityName).trim();
    final category = PlaceCategoryNormalizer.normalize(
      (place['category'] as String? ?? 'tourist').trim(),
    );

    if (name.isEmpty || !PlaceCategoryNormalizer.isAllowed(category)) {
      return;
    }

    final existing = await FirebaseFirestore.instance
        .collection('landmarks')
        .where('name', isEqualTo: name)
        .where('cityId', isEqualTo: cityId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) return;

    final mediaRaw = await _imageService.fetchImages(
      name,
      cityName: cityName,
      category: category,
      count: 7,
    );
    final metaBase =
        '$name $cityName ${PlaceCategoryNormalizer.normalize(category, contextText: name)}';
    final mediaUrls = await _imageService.filterPersistableImageUrls(
      urls: mediaRaw,
      placeName: name,
      cityName: cityName,
      category: category,
      metaTextBase: metaBase,
      findOwnersForImageUrl: _firebase.findLandmarkIdsWithImageUrl,
      excludeLandmarkId: null,
      maxCount: 7,
    );
    final imageUrl = mediaUrls.isNotEmpty ? mediaUrls.first : '';

    await FirebaseFirestore.instance.collection('landmarks').add({
      'name': name,
      'city': cityName,
      'cityId': cityId,
      'category': category,
      'description': address,
      'shortDescription': address,
      'fullDescription': '',
      'history': '',
      'imageUrl': imageUrl,
      'mediaUrls': mediaUrls,
      'lat': lat,
      'lng': lng,
      'address': address,
      'rating': 0,
      'openingHours': '',
      'location': '$lat, $lng',
      'createdAt': DateTime.now().toIso8601String(),
      'imagesRefreshedAt':
          mediaUrls.isNotEmpty ? DateTime.now().toIso8601String() : null,
      'sources': {
        'base': 'curated_or_wikipedia',
        'images': mediaUrls.isNotEmpty ? 'image_service' : 'none',
      },
    });
  }
}