// ============================================================
//  services/firebase_service.dart  (REBUILT)
//
//  All Firestore operations live here.
//  Added: Saved AI Images operations.
// ============================================================

// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models.dart/createCity_model.dart';
import '../models.dart/landmark_model.dart';
import '../models.dart/saved_ai_image_model.dart';
import 'landmark_image_ai_service.dart';

class FirebaseService {
  final FirebaseFirestore _db;

  FirebaseService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // ──────────────────────────────────────────────────────────────
  //  PARTIAL UPDATE  (used by PlaceRepository)
  // ──────────────────────────────────────────────────────────────
  Future<void> partialUpdate(String docId, Map<String, dynamic> fields) async {
    if (docId.trim().isEmpty || fields.isEmpty) return;
    await _db
        .collection('landmarks')
        .doc(docId)
        .set(fields, SetOptions(merge: true));
  }

  // ──────────────────────────────────────────────────────────────
  //  SAVED AI IMAGES
  //  Path: users/{uid}/saved_ai_images/{saveKey}
  // ──────────────────────────────────────────────────────────────

  String buildSavedAiImageKey({
  required String imageBase64,
  required AiImageDetails details,
}) {
  final raw = '${imageBase64.length}|${imageBase64.substring(0, imageBase64.length > 200 ? 200 : imageBase64.length)}';

  int hash = 0;
  for (final unit in raw.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }

  return 'ai_$hash';
}

  Future<void> saveAiImage({
    required String saveKey,
    required String imageBase64,
    required AiImageDetails details,
  }) async {
    final uid = currentUserId;
    if (uid == null || saveKey.trim().isEmpty) return;

    await _db
        .collection('users')
        .doc(uid)
        .collection('saved_ai_images')
        .doc(saveKey.trim())
        .set({
      'imageBase64': imageBase64,
      'title': details.title,
      'location': details.location,
      'content': details.content,
      'historicalFacts': details.historicalFacts,
      'travelTips': details.travelTips,
      'category': details.category,
      'tags': details.tags,
      'savedAt': FieldValue.serverTimestamp(),
      'savedAtClient': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> removeSavedAiImage(String saveKey) async {
    final uid = currentUserId;
    if (uid == null || saveKey.trim().isEmpty) return;

    await _db
        .collection('users')
        .doc(uid)
        .collection('saved_ai_images')
        .doc(saveKey.trim())
        .delete();
  }

  Future<bool> isAiImageSaved(String saveKey) async {
    final uid = currentUserId;
    if (uid == null || saveKey.trim().isEmpty) return false;

    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('saved_ai_images')
        .doc(saveKey.trim())
        .get();

    return doc.exists;
  }

  Stream<bool> savedAiImageStream(String saveKey) {
    final uid = currentUserId;
    if (uid == null || saveKey.trim().isEmpty) return Stream.value(false);

    return _db
        .collection('users')
        .doc(uid)
        .collection('saved_ai_images')
        .doc(saveKey.trim())
        .snapshots()
        .map((doc) => doc.exists);
  }

  Stream<List<SavedAiImage>> savedAiImagesStream() {
    final uid = currentUserId;
    if (uid == null) return const Stream.empty();

    return _db
        .collection('users')
        .doc(uid)
        .collection('saved_ai_images')
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((doc) => SavedAiImage.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // ──────────────────────────────────────────────────────────────
  //  FAVORITES
  // ──────────────────────────────────────────────────────────────
  Future<void> toggleFavorite(Landmark place) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || place.id.trim().isEmpty) return;

    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(place.id);

    final doc = await ref.get();
    if (doc.exists) {
      await ref.delete();
    } else {
      await ref.set(place.toJson(), SetOptions(merge: true));
    }
  }

  Future<bool> isFavorite(String placeId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || placeId.trim().isEmpty) return false;
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(placeId)
        .get();
    return doc.exists;
  }

  Future<List<Landmark>> getUserFavorites() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .get();
    return snap.docs.map((d) => Landmark.fromJson(d.data(), d.id)).toList();
  }

  Stream<bool> favoriteStream(String placeId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null || placeId.trim().isEmpty) return Stream.value(false);
    return _db
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(placeId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  // ──────────────────────────────────────────────────────────────
  //  PLANS
  // ──────────────────────────────────────────────────────────────
  Future<String?> savePlan({
    required List<List<Landmark>> plan,
    String? title,
    required String userId,
  }) async {
    final uid = userId.trim().isNotEmpty ? userId : _auth.currentUser?.uid;
    if (uid == null) return null;

    final formattedDays = plan.asMap().entries.map((entry) {
      return {
        'dayNumber': entry.key + 1,
        'places': entry.value
            .map((p) => {
                  'id': p.id,
                  'name': p.name,
                  'city': p.city,
                  'cityId': p.cityId,
                  'category': p.category,
                  'imageUrl': p.imageUrl,
                  'shortDescription': p.shortDescription,
                  'fullDescription': p.fullDescription,
                  'history': p.history,
                  'rating': p.rating,
                  'lat': p.lat,
                  'lng': p.lng,
                  'address': p.address,
                  'openingHours': p.openingHours,
                  'location': p.location,
                  'mediaUrls': p.mediaUrls,
                  'wikipediaUrl': p.wikipediaUrl,
                })
            .toList(),
      };
    }).toList();

    final totalPlaces = plan.fold<int>(0, (s, d) => s + d.length);
    final daysCount = plan.length;
    final allPlaces = plan.expand((e) => e).toList();
    final firstPlace = allPlaces.isNotEmpty ? allPlaces.first : null;
    final cityName = firstPlace?.city ?? 'Egypt';
    final cityId = firstPlace?.cityId ?? '';

    final ref = await _db.collection('users').doc(uid).collection('plans').add({
      'title': (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : '$cityName $daysCount-day plan',
      'daysCount': daysCount,
      'placesCount': totalPlaces,
      'city': cityName,
      'cityId': cityId,
      'days': formattedDays,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtClient': DateTime.now().toIso8601String(),
    });

    return ref.id;
  }

  Stream<List<Map<String, dynamic>>> userPlansStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _db
        .collection('users')
        .doc(uid)
        .collection('plans')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
      return snap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  Future<void> deletePlan(String planId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || planId.trim().isEmpty) return;
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('plans')
        .doc(planId.trim());
    final doc = await ref.get();
    if (!doc.exists) return;
    await ref.delete();
  }

  // ──────────────────────────────────────────────────────────────
  //  VISITED
  // ──────────────────────────────────────────────────────────────
  Future<void> toggleVisited(Landmark place) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || place.id.trim().isEmpty) return;
    final ref =
        _db.collection('users').doc(uid).collection('visited').doc(place.id);
    final doc = await ref.get();
    if (doc.exists) {
      await ref.delete();
    } else {
      await ref.set({
        ...place.toJson(),
        'visitedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Stream<bool> visitedStream(String placeId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null || placeId.trim().isEmpty) return Stream.value(false);
    return _db
        .collection('users')
        .doc(uid)
        .collection('visited')
        .doc(placeId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  // ──────────────────────────────────────────────────────────────
  //  BOOKING LINKS
  // ──────────────────────────────────────────────────────────────
  Stream<Map<String, String>> bookingLinksStream(String placeId) {
    if (placeId.trim().isEmpty) return Stream.value({});
    return _db
        .collection('landmarks')
        .doc(placeId)
        .collection('bookingLinks')
        .snapshots()
        .map((snap) {
      final result = <String, String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final title = (data['title'] as String? ?? '').trim();
        final url = (data['url'] as String? ?? '').trim();
        if (title.isNotEmpty && url.isNotEmpty) result[title] = url;
      }
      return result;
    });
  }

  // ──────────────────────────────────────────────────────────────
  //  REVIEWS & RATINGS
  // ──────────────────────────────────────────────────────────────
  Future<void> addReview({
    required String placeId,
    required double rating,
    required String comment,
  }) async {
    final uid = _auth.currentUser?.uid;
    final userName = _auth.currentUser?.displayName ?? 'User';
    if (uid == null || placeId.trim().isEmpty) return;

    await _db.collection('landmarks').doc(placeId).collection('reviews').doc(uid).set({
      'userId': uid,
      'userName': userName,
      'rating': rating,
      'comment': comment.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<Map<String, dynamic>>> reviewsStream(String placeId) {
    if (placeId.trim().isEmpty) return const Stream.empty();
    return _db
        .collection('landmarks')
        .doc(placeId)
        .collection('reviews')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  Stream<double> averageRatingStream(String placeId) {
    return reviewsStream(placeId).map((reviews) {
      if (reviews.isEmpty) return 0.0;
      double total = 0;
      for (final r in reviews) {
        total += ((r['rating'] ?? 0) as num).toDouble();
      }
      return total / reviews.length;
    });
  }

  Future<void> deleteReview({
    required String placeId,
    required String userId,
  }) async {
    if (placeId.trim().isEmpty || userId.trim().isEmpty) return;
    await _db
        .collection('landmarks')
        .doc(placeId)
        .collection('reviews')
        .doc(userId)
        .delete();
  }

  // ──────────────────────────────────────────────────────────────
  //  NEARBY SUGGESTIONS
  // ──────────────────────────────────────────────────────────────
  Stream<List<Landmark>> nearbySuggestionsStream({
    required String city,
    required String excludePlaceId,
    required double sourceLat,
    required double sourceLng,
    double maxDistanceKm = 15,
  }) {
    if (city.trim().isEmpty) return Stream.value([]);

    return _db.collection('landmarks').where('city', isEqualTo: city).snapshots().map((snap) {
      final all = snap.docs
          .map((d) => Landmark.fromJson(d.data(), d.id))
          .where((lm) => lm.id != excludePlaceId)
          .toList();

      if (sourceLat != 0 && sourceLng != 0) {
        final withDist = all.map((lm) {
          final d = _distanceKm(sourceLat, sourceLng, lm.lat, lm.lng);
          return MapEntry(lm, d);
        }).toList();

        final close = withDist
            .where((e) => e.value.isFinite && e.value <= maxDistanceKm)
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));

        if (close.isNotEmpty) {
          return close.map((e) => e.key).toList();
        }
      }

      all.sort((a, b) => b.rating.compareTo(a.rating));
      return all.take(30).toList();
    });
  }

  // ──────────────────────────────────────────────────────────────
  //  CITIES
  // ──────────────────────────────────────────────────────────────
  Future<List<City>> getCities() async {
    final snap = await _db.collection('cities').orderBy('name').get();
    return snap.docs.map((d) => City.fromJson(d.data(), d.id)).toList();
  }

  Future<String> addCity(City city) async {
    final ref = await _db.collection('cities').add(city.toJson());
    return ref.id;
  }

  Future<City?> getCityByName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    final normalized = trimmed.toLowerCase();
    final snap = await _db.collection('cities').get();

    for (final doc in snap.docs) {
      final city = City.fromJson(doc.data(), doc.id);
      final cityName = city.name.trim().toLowerCase();
      if (cityName == normalized ||
          cityName.contains(normalized) ||
          normalized.contains(cityName)) {
        return city;
      }
    }
    return null;
  }

  Future<City> findOrCreateCityByName(
    String name, {
    double? lat,
    double? lng,
  }) async {
    final existing = await getCityByName(name);
    if (existing != null) return existing;

    final cleanName = name.trim().isEmpty ? 'Unknown City' : name.trim();
    final city = City(
      id: '',
      name: cleanName,
      image: '',
      lat: lat ?? 0,
      lng: lng ?? 0,
    );
    final id = await addCity(city);
    return city.copyWith(id: id);
  }

  // ──────────────────────────────────────────────────────────────
  //  LANDMARKS – Read
  // ──────────────────────────────────────────────────────────────
  Future<Landmark?> getLandmarkById(String placeId) async {
    final id = placeId.trim();
    if (id.isEmpty) return null;
    try {
      final doc = await _db.collection('landmarks').doc(id).get();
      if (!doc.exists || doc.data() == null) return null;
      return Landmark.fromJson(doc.data()!, doc.id);
    } catch (e) {
      print('getLandmarkById error: $e');
      return null;
    }
  }

  Stream<Landmark?> streamLandmarkById(String placeId) {
    final id = placeId.trim();
    if (id.isEmpty) return Stream.value(null);
    return _db.collection('landmarks').doc(id).snapshots().map((doc) {
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return Landmark.fromJson(data, doc.id);
    });
  }

  Future<List<Landmark>> getAllLandmarks() async {
    final snap = await _db.collection('landmarks').get();
    return snap.docs.map((d) => Landmark.fromJson(d.data(), d.id)).toList();
  }

  Future<List<Landmark>> getLandmarksByCity(String cityId) async {
    if (cityId.trim().isEmpty) return [];
    final snap = await _db
        .collection('landmarks')
        .where('cityId', isEqualTo: cityId)
        .orderBy('name')
        .get();
    return snap.docs.map((d) => Landmark.fromJson(d.data(), d.id)).toList();
  }

  // ──────────────────────────────────────────────────────────────
  //  LANDMARKS – Write
  // ──────────────────────────────────────────────────────────────
  Future<String> saveLandmark(Landmark landmark) async {
    final effectiveCity =
        landmark.city.trim().isNotEmpty ? landmark.city.trim() : '';

    if (effectiveCity.isEmpty || effectiveCity.toLowerCase() == 'egypt') {
      throw Exception('Cannot save landmark without a specific city.');
    }

    final actualCity = await findOrCreateCityByName(
      effectiveCity,
      lat: landmark.lat != 0 ? landmark.lat : null,
      lng: landmark.lng != 0 ? landmark.lng : null,
    );

    final normalized = landmark.copyWith(
      cityId: actualCity.id,
      city: actualCity.name,
      description: landmark.description.trim().isNotEmpty
          ? landmark.description.trim()
          : landmark.shortDescription.trim(),
      shortDescription: landmark.shortDescription.trim().isNotEmpty
          ? landmark.shortDescription.trim()
          : landmark.description.trim(),
      createdAt: landmark.createdAt ?? DateTime.now(),
    );

    final existing = await _db
        .collection('landmarks')
        .where('cityId', isEqualTo: normalized.cityId)
        .where('name', isEqualTo: normalized.name)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      final docId = existing.docs.first.id;
      final existingData = existing.docs.first.data();

      final updateMap = _buildMergeMap(existingData, normalized);
      if (updateMap.isNotEmpty) {
        await _db.collection('landmarks').doc(docId).set(updateMap, SetOptions(merge: true));
      }
      return docId;
    }

    final ref = await _db.collection('landmarks').add(normalized.toJson());
    return ref.id;
  }

  Map<String, dynamic> _buildMergeMap(
    Map<String, dynamic> existing,
    Landmark incoming,
  ) {
    final map = <String, dynamic>{
      'city': incoming.city,
      'cityId': incoming.cityId,
    };

    void setText(String key, String newVal, String existingVal) {
      final n = newVal.trim();
      final e = existingVal.trim();
      if (n.isNotEmpty && n.length > e.length) map[key] = n;
    }

    setText('description', incoming.description, (existing['description'] ?? '').toString());
    setText('shortDescription', incoming.shortDescription, (existing['shortDescription'] ?? '').toString());
    setText('fullDescription', incoming.fullDescription, (existing['fullDescription'] ?? '').toString());
    setText('history', incoming.history, (existing['history'] ?? '').toString());
    setText('address', incoming.address, (existing['address'] ?? '').toString());
    setText('openingHours', incoming.openingHours, (existing['openingHours'] ?? '').toString());

    final existingMedia = List<String>.from(existing['mediaUrls'] as List? ?? const []);
    final merged = _mergeMediaUrls(existingMedia, incoming.mediaUrls, incoming.imageUrl);
    if (merged.length > existingMedia.length) {
      map['mediaUrls'] = merged;
      if (incoming.imageUrl.trim().isNotEmpty &&
          (existing['imageUrl'] ?? '').toString().trim().isEmpty) {
        map['imageUrl'] = incoming.imageUrl.trim();
      }
    }

    final existingRating = ((existing['rating'] ?? 0) as num).toDouble();
    if (incoming.rating > existingRating) {
      map['rating'] = incoming.rating;
    }

    final existingLat = ((existing['lat'] ?? 0) as num).toDouble();
    final existingLng = ((existing['lng'] ?? 0) as num).toDouble();
    if ((existingLat == 0 || existingLng == 0) &&
        incoming.lat != 0 &&
        incoming.lng != 0) {
      map['lat'] = incoming.lat;
      map['lng'] = incoming.lng;
      map['location'] = '${incoming.lat}, ${incoming.lng}';
    }

    if (incoming.wikipediaUrl != null && incoming.wikipediaUrl!.trim().isNotEmpty) {
      map['wikipediaUrl'] = incoming.wikipediaUrl!.trim();
    }

    if (incoming.wikiEnrichedAt != null) {
      map['wikiEnrichedAt'] = incoming.wikiEnrichedAt!.toIso8601String();
    }
    if (incoming.imagesRefreshedAt != null) {
      map['imagesRefreshedAt'] = incoming.imagesRefreshedAt!.toIso8601String();
    }
    if (incoming.nearbyUpdatedAt != null) {
      map['nearbyUpdatedAt'] = incoming.nearbyUpdatedAt!.toIso8601String();
    }

    return map;
  }

  List<String> _mergeMediaUrls(
    List<String> old,
    List<String> incoming,
    String mainUrl,
  ) {
    final seen = <String>{};
    final result = <String>[];

    void add(String url) {
      final clean = url.trim();
      if (clean.isNotEmpty && seen.add(clean)) result.add(clean);
    }

    add(mainUrl);
    for (final u in old) add(u);
    for (final u in incoming) add(u);

    return result.take(7).toList();
  }

  Future<Map<String, String>> saveLandmarks(List<Landmark> landmarks) async {
    final result = <String, String>{};
    for (final lm in landmarks) {
      try {
        final docId = await saveLandmark(lm);
        result[lm.name] = docId;
      } catch (_) {}
    }
    return result;
  }

  Future<bool> cityHasLandmarks(String cityId) async {
    if (cityId.trim().isEmpty) return false;
    final snap = await _db
        .collection('landmarks')
        .where('cityId', isEqualTo: cityId)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  // ──────────────────────────────────────────────────────────────
  //  WIKIPEDIA ENRICHMENT
  // ──────────────────────────────────────────────────────────────
  Future<void> enrichLandmarkWithWikipedia({
    required String docId,
    required String shortDescription,
    required String fullDescription,
    required String history,
    required String wikipediaUrl,
  }) async {
    if (docId.trim().isEmpty) return;

    final updateMap = <String, dynamic>{};
    if (shortDescription.trim().isNotEmpty) {
      updateMap['description'] = shortDescription.trim();
      updateMap['shortDescription'] = shortDescription.trim();
    }
    if (fullDescription.trim().isNotEmpty) {
      updateMap['fullDescription'] = fullDescription.trim();
    }
    if (history.trim().isNotEmpty) {
      updateMap['history'] = history.trim();
    }
    if (wikipediaUrl.trim().isNotEmpty) {
      updateMap['wikipediaUrl'] = wikipediaUrl.trim();
    }
    updateMap['wikiEnrichedAt'] = DateTime.now().toIso8601String();

    if (updateMap.isNotEmpty) {
      await _db.collection('landmarks').doc(docId).set(updateMap, SetOptions(merge: true));
    }
  }

  // ──────────────────────────────────────────────────────────────
  //  MIGRATION UTILITY
  // ──────────────────────────────────────────────────────────────
  Future<void> fixCorruptLandmarkCityIds() async {
    print('Starting cityId migration...');
    final citiesSnap = await _db.collection('cities').get();
    final nameToDocId = <String, String>{};
    for (final doc in citiesSnap.docs) {
      final name = (doc.data()['name'] as String? ?? '').trim();
      nameToDocId[name.toLowerCase()] = doc.id;
    }

    final validDocIds = nameToDocId.values.toSet();
    final landmarksSnap = await _db.collection('landmarks').get();
    final batch = _db.batch();
    int fixed = 0;

    for (final doc in landmarksSnap.docs) {
      final data = doc.data();
      final currentCityId = data['cityId'] as String? ?? '';
      if (validDocIds.contains(currentCityId)) continue;

      final cityNameInDoc = (data['city'] as String? ?? '').trim();
      final correctDocId = nameToDocId[cityNameInDoc.toLowerCase()];

      if (correctDocId != null) {
        batch.update(doc.reference, {'cityId': correctDocId});
        fixed++;
      }
    }

    if (fixed > 0) {
      await batch.commit();
      print('Fixed $fixed corrupt city IDs.');
    } else {
      print('No corrupt city IDs found.');
    }
  }

  Future<void> saveRemoteNearbyPlaces({
    required String cityName,
    required List<Map<String, dynamic>> places,
  }) async {
    for (final item in places) {
      try {
        final name = (item['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        final cityDoc = await findOrCreateCityByName(cityName);
        final existing = await _db
            .collection('landmarks')
            .where('cityId', isEqualTo: cityDoc.id)
            .where('name', isEqualTo: name)
            .limit(1)
            .get();

        if (existing.docs.isNotEmpty) continue;

        await _db.collection('landmarks').add({
          'name': name,
          'city': cityName,
          'cityId': cityDoc.id,
          'category': (item['category'] ?? 'tourist').toString(),
          'description': (item['shortDescription'] ?? '').toString(),
          'shortDescription': (item['shortDescription'] ?? '').toString(),
          'fullDescription': (item['fullDescription'] ?? '').toString(),
          'history': (item['history'] ?? '').toString(),
          'imageUrl': (item['imageUrl'] ?? '').toString(),
          'mediaUrls': item['mediaUrls'] ?? [],
          'lat': ((item['lat'] ?? 0) as num).toDouble(),
          'lng': ((item['lng'] ?? 0) as num).toDouble(),
          'address': (item['address'] ?? cityName).toString(),
          'rating': ((item['rating'] ?? 0) as num).toDouble(),
          'openingHours': (item['openingHours'] ?? '').toString(),
          'location': '',
          'createdAt': DateTime.now().toIso8601String(),
          'nearbyUpdatedAt':
              (item['nearbyRefreshedAt'] ?? DateTime.now().toIso8601String()),
        });
      } catch (_) {}
    }
  }

  // ──────────────────────────────────────────────────────────────
  //  GEOMETRY
  // ──────────────────────────────────────────────────────────────
  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    if (lat1 == 0 || lng1 == 0 || lat2 == 0 || lng2 == 0) {
      return double.infinity;
    }
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            (math.sin(dLng / 2) * math.sin(dLng / 2));
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degToRad(double deg) => deg * (math.pi / 180.0);
}
