// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math' as math;

import 'package:geoguide/models.dart/createCity_model.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/core/place_category_normalizer.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/services/image-service.dart';
import 'package:geoguide/services/landmark_cache.dart';
import 'package:geoguide/services/nearby-service.dart';
import 'package:geoguide/services/Wikipedia%20service.dart';

class PlaceRepository {
  PlaceRepository({
    FirebaseService? firebase,
    ImageService? images,
    WikipediaService? wikipedia,
    NearbyService? nearby,
  })  : _firebase = firebase ?? FirebaseService(),
        _images = images ?? ImageService(),
        _wikipedia = wikipedia ?? WikipediaService(),
        _nearby = nearby ?? NearbyService(),
        _cache = LandmarkCache.instance;

  final FirebaseService _firebase;
  final ImageService _images;
  final WikipediaService _wikipedia;
  final NearbyService _nearby;
  final LandmarkCache _cache;

  final Map<String, StreamSubscription<Landmark?>> _firestoreSubs = {};
  final Set<String> _enrichingImages = {};
  final Set<String> _enrichingWiki = {};
  final Set<String> _enrichingNearby = {};

  Landmark? get(String id) => _cache.get(id);
  bool needsImageRefresh(String id) => _cache.needsImageRefresh(id);
  bool needsWikiRefresh(String id) => _cache.needsWikiRefresh(id);
  bool needsNearbyRefresh(String id) => _cache.needsNearbyRefresh(id);

  Stream<Landmark> streamLandmark(String id) {
    if (id.trim().isEmpty) return const Stream.empty();

    if (!_firestoreSubs.containsKey(id)) {
      _firestoreSubs[id] = _firebase.streamLandmarkById(id).listen((fresh) {
        if (fresh != null) _cache.merge(fresh);
      });
    }

    final current = _cache.get(id);
    if (current != null) Future.microtask(() => _cache.put(current));
    return _cache.stream(id);
  }

  Future<List<Landmark>> loadCity(String cityId) async {
    final list = await _firebase.getLandmarksByCity(cityId);
    final valid = _filterAndNormalize(list);
    for (final lm in valid) {
      _cache.merge(lm);
    }
    return valid;
  }

  Future<List<Landmark>> loadAll() async {
    final list = await _firebase.getAllLandmarks();
    final valid = _filterAndNormalize(list);
    for (final lm in valid) {
      _cache.merge(lm);
    }
    return valid;
  }

  Future<String> save(Landmark landmark) async {
    final id = await _firebase.saveLandmark(landmark);
    final saved = landmark.id.isEmpty ? landmark.copyWith(id: id) : landmark;
    _cache.merge(saved);
    return id;
  }

  Future<void> enrichImages(Landmark landmark) async {
    final id = landmark.id.trim();
    if (id.isEmpty || _enrichingImages.contains(id)) return;
    if (!_cache.needsImageRefresh(id)) return;

    _enrichingImages.add(id);
    try {
      // Before calling external image APIs, read the latest Firestore copy.
      // This prevents re-fetching images after app restart when the current
      // screen was opened with an older/stale Landmark object.
      final latestFromDb = await _firebase.getLandmarkById(id);
      if (latestFromDb != null) {
        _cache.merge(latestFromDb);
        if (!_cache.needsImageRefresh(id)) {
          print('[PlaceRepository] images already cached for ${latestFromDb.name}; skip API fetch.');
          return;
        }
      }

      final existing = _cache.get(id) ?? latestFromDb ?? landmark;
      final fetched = await _images.fetchImages(
        existing.name,
        cityName: existing.city,
        category: existing.category,
        count: 6,
        excludeUrls: [existing.imageUrl, ...existing.mediaUrls],
      );
      if (fetched.isEmpty) return;

      final merged = _mergeUrls(existing.imageUrl, existing.mediaUrls, fetched);
      final updated = existing.copyWith(
        imageUrl: merged.isNotEmpty ? merged.first : existing.imageUrl,
        mediaUrls: merged,
        imagesRefreshedAt: DateTime.now(),
        imagePipelineVersion: ImageService.imagePipelineVersion,
        imagesAreFallback: false,
      );
      _cache.merge(updated);
      await _firebase.partialUpdate(id, {
        'imageUrl': updated.imageUrl,
        'mediaUrls': updated.mediaUrls,
        'imagesRefreshedAt': updated.imagesRefreshedAt!.toIso8601String(),
        'imagePipelineVersion': ImageService.imagePipelineVersion,
        'imagesAreFallback': false,
      });
    } catch (e) {
      print('[PlaceRepository] enrichImages error: $e');
    } finally {
      _enrichingImages.remove(id);
    }
  }

  Future<void> enrichWikipedia(Landmark landmark) async {
    final id = landmark.id.trim();
    if (id.isEmpty || _enrichingWiki.contains(id)) return;
    if (!_cache.needsWikiRefresh(id)) return;

    _enrichingWiki.add(id);
    try {
      final existing = _cache.get(id) ?? landmark;
      final result = await _wikipedia.search(existing.name, cityName: existing.city);
      if (result == null) return;

      String history = '';
      try {
        history = _wikipedia.extractHistorySection(result.fullText).trim();
      } catch (_) {}

      final updated = existing.copyWith(
        shortDescription: result.summary.trim().isNotEmpty ? result.summary.trim() : existing.shortDescription,
        fullDescription: result.fullText.trim().isNotEmpty ? result.fullText.trim() : existing.fullDescription,
        history: history.isNotEmpty ? history : (result.fullText.trim().isNotEmpty ? result.fullText.trim() : existing.history),
        wikipediaUrl: result.pageUrl,
        wikiEnrichedAt: DateTime.now(),
      );

      _cache.merge(updated);
      await _firebase.enrichLandmarkWithWikipedia(
        docId: id,
        shortDescription: updated.shortDescription,
        fullDescription: updated.fullDescription,
        history: updated.history,
        wikipediaUrl: updated.wikipediaUrl ?? '',
      );
    } catch (e) {
      print('[PlaceRepository] enrichWikipedia error: $e');
    } finally {
      _enrichingWiki.remove(id);
    }
  }

  Future<void> enrichNearby(Landmark landmark) async {
    final id = landmark.id.trim();
    if (id.isEmpty || _enrichingNearby.contains(id)) return;

    final provider = (landmark.sources?['provider'] ?? '').toString();
    final category = PlaceCategoryNormalizer.normalize(
      landmark.category,
      contextText: landmark.name,
    );

    // Category search already returns nearby/category POIs from Overpass/Nominatim.
    // Running another nearby lookup for each cafe/restaurant/hotel immediately
    // after search causes many Overpass timeouts and slow image/card loading.
    if ((provider == 'nearby_overpass' ||
            provider == 'nominatim_category' ||
            provider == 'known_landmark_fallback') &&
        (category == 'cafe' || category == 'restaurant' || category == 'hotel')) {
      return;
    }

    if (!_cache.needsNearbyRefresh(id)) return;
    if (landmark.lat == 0 || landmark.lng == 0) return;

    _enrichingNearby.add(id);
    try {
      final existing = _cache.get(id) ?? landmark;
      print('[Nearby] start for ${existing.name} at ${existing.lat}, ${existing.lng}');

      final existingNearby = existing.nearbyPlaces
          .map((e) => NearbyPlace.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      final result = await _nearby.getNearbyWithAutoRefresh(
        lat: existing.lat,
        lng: existing.lng,
        existingPlaces: existingNearby,
        lastFetchedAt: existing.nearbyUpdatedAt,
        limit: 36,
        categories: const [
          'hotel',
          'restaurant',
          'cafe',
          'tourist',
          'outing',
        ], cityName: existing.city,
      );

      List<NearbyPlace> resolved = result.places;
      print('[Nearby] service result count = ${resolved.length}');

      if (resolved.length < 8) {
        final cityLandmarks = await _firebase.getLandmarksByCity(existing.cityId);

        final fallback = cityLandmarks
            .where((lm) => lm.id != existing.id)
            .where(
              (lm) => PlaceCategoryNormalizer.isAllowed(
                lm.category,
                contextText: lm.name,
              ),
            )
            .where((lm) => lm.lat != 0 && lm.lng != 0)
            .map(
              (lm) => NearbyPlace(
                placeId: lm.id,
                name: lm.name,
                address: lm.address.isNotEmpty ? lm.address : lm.city,
                lat: lm.lat,
                lng: lm.lng,
                distanceKm: _distanceKm(
                  existing.lat,
                  existing.lng,
                  lm.lat,
                  lm.lng,
                ),
                rating: lm.rating,
                userRatingsTotal: 0,
                priceLevel: '',
                isOpenNow: false,
                hasOpeningHours: lm.openingHours.trim().isNotEmpty,
                imageUrl: lm.imageUrl,
                category: PlaceCategoryNormalizer.normalize(
                  lm.category,
                  contextText: lm.name,
                ),
                types: const [],
                mapsUrl:
                    'https://www.google.com/maps/search/?api=1&query=${lm.lat},${lm.lng}',
                bookingUrl: null,
                wikipediaUrl: lm.wikipediaUrl,
                phone: null,
                website: null,
                fetchedAt: DateTime.now(),
              ),
            )
            .where((p) => p.distanceKm <= 25)
            .toList()
          ..sort((a, b) {
            final dist = a.distanceKm.compareTo(b.distanceKm);
            if (dist != 0) return dist;
            return b.rating.compareTo(a.rating);
          });

        final mergedMap = <String, NearbyPlace>{};

        for (final p in resolved) {
          final key =
              '${p.name.trim().toLowerCase()}|${p.category}|${p.lat.toStringAsFixed(4)}|${p.lng.toStringAsFixed(4)}';
          mergedMap[key] = p;
        }

        for (final p in fallback) {
          final key =
              '${p.name.trim().toLowerCase()}|${p.category}|${p.lat.toStringAsFixed(4)}|${p.lng.toStringAsFixed(4)}';
          mergedMap.putIfAbsent(key, () => p);
        }

        resolved = mergedMap.values.toList()
          ..sort((a, b) {
            final dist = a.distanceKm.compareTo(b.distanceKm);
            if (dist != 0) return dist;
            return b.rating.compareTo(a.rating);
          });

        if (resolved.length > 36) {
          resolved = resolved.take(36).toList();
        }
      }

      print('[Nearby] final result count = ${resolved.length}');
      if (resolved.isEmpty) return;

      final updated = existing.copyWith(
        nearbyPlaces: resolved.map((p) => p.toJson()).toList(),
        nearbyUpdatedAt: result.refreshedAt,
      );

      _cache.merge(updated);

      await _firebase.partialUpdate(id, {
        'nearbyPlaces': updated.nearbyPlaces,
        'nearbyUpdatedAt': updated.nearbyUpdatedAt!.toIso8601String(),
      });
    } catch (e) {
      print('[PlaceRepository] enrichNearby error: $e');
    } finally {
      _enrichingNearby.remove(id);
    }
  }

  Stream<bool> favoriteStream(String placeId) => _firebase.favoriteStream(placeId);
  Stream<bool> visitedStream(String placeId) => _firebase.visitedStream(placeId);
  Future<void> toggleFavorite(Landmark place) => _firebase.toggleFavorite(place);
  Future<void> toggleVisited(Landmark place) => _firebase.toggleVisited(place);
  Future<List<Landmark>> getUserFavorites() => _firebase.getUserFavorites();
  Stream<List<Map<String, dynamic>>> reviewsStream(String placeId) => _firebase.reviewsStream(placeId);
  Stream<double> averageRatingStream(String placeId) => _firebase.averageRatingStream(placeId);
  Future<void> addReview({required String placeId, required double rating, required String comment}) =>
      _firebase.addReview(placeId: placeId, rating: rating, comment: comment);
  Future<void> deleteReview({required String placeId, required String userId}) =>
      _firebase.deleteReview(placeId: placeId, userId: userId);
  Stream<Map<String, String>> bookingLinksStream(String placeId) => _firebase.bookingLinksStream(placeId);
  Future<List<City>> getCities() => _firebase.getCities();

  List<Landmark> _filterAndNormalize(List<Landmark> raw) {
    final deduped = <String, Landmark>{};
    for (final lm in raw) {
      if (lm.city.trim().isEmpty || lm.city.trim().toLowerCase() == 'egypt') continue;
      if (!PlaceCategoryNormalizer.isAllowed(lm.category, contextText: lm.name)) continue;
      final normalized = lm.copyWith(
        category: PlaceCategoryNormalizer.normalize(lm.category, contextText: lm.name),
      );
      final key = '${normalized.name.trim().toLowerCase()}|${normalized.city.trim().toLowerCase()}';
      deduped[key] = normalized;
    }
    return deduped.values.toList();
  }

  List<String> _mergeUrls(String mainUrl, List<String> existing, List<String> fetched) {
    final seen = <String>{};
    final result = <String>[];

    void add(String url) {
      final clean = url.trim();
      if (clean.isEmpty || !clean.startsWith('http')) return;
      final key = Uri.tryParse(clean)
              ?.replace(query: '', fragment: '')
              .toString()
              .toLowerCase() ??
          clean.toLowerCase();
      if (seen.add(key)) result.add(clean);
    }

    // New verified images first. Existing images may belong to an older pipeline.
    for (final u in fetched) add(u);
    add(mainUrl);
    for (final u in existing) add(u);

    return result.take(6).toList();
  }

  List<String> _validUrls(List<String> urls) =>
      urls.map((e) => e.trim()).where((e) => e.startsWith('http')).toList();

  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
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

  double _degToRad(double deg) => deg * (math.pi / 180.0);
}
