// ============================================================
//  services/place_repository.dart
//  Fixed version: early-skip automatic image enrichment for
//  admin-edited landmarks before any image API request.
// ============================================================

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geoguide/core/place_category_normalizer.dart';
import 'package:geoguide/models.dart/createCity_model.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/services/image-service.dart';
import 'package:geoguide/services/landmark_cache.dart';
import 'package:geoguide/services/nearby-service.dart';
import 'Wikipedia service.dart';

class PlaceRepository {
  PlaceRepository({
    FirebaseService? firebase,
    ImageService? images,
    WikipediaService? wikipedia,
    NearbyService? nearby,
  })  : _firebase = firebase ?? FirebaseService(),
        _images = images ?? ImageService(),
        _wikipedia = wikipedia ?? WikipediaService(),
        _nearby = nearby ?? NearbyService();

  final FirebaseService _firebase;
  final ImageService _images;
  final WikipediaService _wikipedia;
  final NearbyService _nearby;
  final LandmarkCache _cache = LandmarkCache.instance;

  final Map<String, Landmark> _memory = <String, Landmark>{};

  final Set<String> _enrichingImages = <String>{};
  final Set<String> _enrichingWiki = <String>{};
  final Set<String> _enrichingNearby = <String>{};

  static const Duration _imageTtl = Duration(days: 21);
  static const Duration _wikiTtl = Duration(days: 30);
  static const Duration _nearbyTtl = Duration(days: 7);

  Landmark? get(String id) {
    final key = id.trim();
    if (key.isEmpty) return null;
    return _memory[key];
  }

  void put(Landmark landmark) {
    final id = landmark.id.trim();
    if (id.isEmpty) return;
    _memory[id] = landmark;
    _cache.put(landmark);
  }

  void merge(Landmark landmark) {
    final id = landmark.id.trim();
    if (id.isEmpty) return;
    _memory[id] = landmark;
    _cache.merge(landmark);
  }

  Stream<Landmark> streamLandmark(String placeId) {
    final id = placeId.trim();
    if (id.isEmpty) {
      return const Stream<Landmark>.empty();
    }

    return _firebase.streamLandmarkById(id).where((lm) => lm != null).map((lm) {
      final fresh = lm!;
      _memory[id] = fresh;
      _cache.merge(fresh);
      return fresh;
    });
  }

  Future<Landmark?> getLandmarkById(String placeId) async {
    final fresh = await _firebase.getLandmarkById(placeId);
    if (fresh != null) merge(fresh);
    return fresh;
  }

  Future<List<Landmark>> getAllLandmarks() async {
    final list = await _firebase.getAllLandmarks();
    final filtered = _filterAndNormalize(list);
    for (final lm in filtered) {
      merge(lm);
    }
    return filtered;
  }

  Future<List<Landmark>> getLandmarksByCity(String cityId) async {
    final list = await _firebase.getLandmarksByCity(cityId);
    final filtered = _filterAndNormalize(list);
    for (final lm in filtered) {
      merge(lm);
    }
    return filtered;
  }

  // Compatibility wrappers used by Home screens and older code paths.
  Future<List<Landmark>> loadAll() => getAllLandmarks();

  Future<List<Landmark>> loadCity(String cityId) => getLandmarksByCity(cityId);

  Future<String> save(Landmark landmark) async {
    final id = await _firebase.saveLandmark(landmark);
    final fresh = await _firebase.getLandmarkById(id);
    if (fresh != null) merge(fresh);
    return id;
  }

  Future<Map<String, String>> saveAll(List<Landmark> landmarks) async {
    final result = await _firebase.saveLandmarks(landmarks);
    for (final id in result.values) {
      final fresh = await _firebase.getLandmarkById(id);
      if (fresh != null) merge(fresh);
    }
    return result;
  }

  bool needsImageRefresh(String placeId, {bool force = false}) {
    if (force) return true;
    final lm = get(placeId);
    if (lm == null) return true;
    if (lm.imageUrl.trim().isEmpty && lm.mediaUrls.isEmpty) return true;
    final at = lm.imagesRefreshedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > _imageTtl;
  }

  bool needsWikiRefresh(String placeId, {bool force = false}) {
    if (force) return true;
    final lm = get(placeId);
    if (lm == null) return true;
    final hasEnoughText = lm.shortDescription.trim().length >= 60 &&
        lm.fullDescription.trim().length >= 100;
    if (!hasEnoughText) return true;
    final at = lm.wikiEnrichedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > _wikiTtl;
  }

  bool needsNearbyRefresh(String placeId, {bool force = false}) {
    if (force) return true;
    final lm = get(placeId);
    if (lm == null) return true;
    if (lm.nearbyPlaces.isEmpty) return true;
    final at = lm.nearbyUpdatedAt ?? lm.nearbyRefreshedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > _nearbyTtl;
  }

  Future<void> enrichImages(
    Landmark landmark, {
    bool force = false,
    String imageUpdateSource = 'background_image_enrichment',
    bool allowAdminImageOverwrite = false,
  }) async {
    final id = landmark.id.trim();
    if (id.isEmpty) return;
    if (_enrichingImages.contains(id)) return;

    final isExplicitAdminImageRefresh =
        imageUpdateSource == 'admin_image_refresh' || allowAdminImageOverwrite;

    if (isExplicitAdminImageRefresh && kDebugMode) {
      debugPrint('[ImageEnrichAdminRefreshAllowed] doc=$id place=${landmark.name}');
    }

    // Critical fix: for admin-edited docs, automatic/background image enrichment
    // must stop BEFORE calling ImageService / Wikipedia / Commons / stock APIs.
    // force=true is NOT treated as admin refresh because runtime logs showed it
    // can be triggered automatically.
    if (!isExplicitAdminImageRefresh) {
      final isAdminEdited = await _firebase.isLandmarkAdminEdited(id);
      if (isAdminEdited) {
        if (kDebugMode) {
          debugPrint(
            '[ImageEnrichSkipAdminDoc] doc=$id reason=admin_edited_background_request',
          );
          debugPrint(
            '[Images] skippedFirebaseImageWrite=true place=${landmark.name} reason=admin_edited_auto_enrichment',
          );
        }
        return;
      }
    }

    final cached = get(id);
    final base = cached ?? landmark;

    if (!force && !needsImageRefresh(id)) {
      if (kDebugMode) {
        debugPrint('[PlaceRepository] images already cached for ${base.name}; skip API fetch.');
      }
      return;
    }

    _enrichingImages.add(id);
    try {
      final normalizedCategory = PlaceCategoryNormalizer.normalize(
        base.category,
        contextText: base.name,
      );

      if (kDebugMode) {
        debugPrint(
          '[Images] enrichImages force=$force place=${base.name} city=${base.city} category=${base.category} normalizedCategory=$normalizedCategory',
        );
      }

      final urlsRaw = await _images.fetchImages(
        base.name,
        displayName: base.displayName.trim().isNotEmpty ? base.displayName : base.name,
        cityName: base.city,
        category: normalizedCategory,
        count: 6,
        excludeUrls: base.mediaUrls,
        forceRefresh: force,
      );

      if (urlsRaw.isEmpty) {
        final failedAt = DateTime.now();
        final failed = base.copyWith(
          imagesFailedAt: failedAt,
          imagesFailureReason: 'no_images_returned',
        );
        merge(failed);
        await _firebase.partialUpdate(id, {
          'imagesFailedAt': failedAt.toIso8601String(),
          'imagesFailureReason': 'no_images_returned',
          'updatedAt': failedAt.toIso8601String(),
          'imageUpdateSource': imageUpdateSource,
        });
        return;
      }

      final metaBase = '${base.name} ${base.city} $normalizedCategory';
      final accepted = await _images.filterPersistableImageUrls(
        urls: urlsRaw,
        placeName: base.name,
        cityName: base.city,
        category: normalizedCategory,
        metaTextBase: metaBase,
        findOwnersForImageUrl: _firebase.findLandmarkIdsWithImageUrl,
        excludeLandmarkId: id,
        allowDuplicateOwnersForSamePlace: (url, ownerIds) =>
            _firebase.imageOwnersAllowHeroSharingWithSubject(base, ownerIds),
        maxCount: 6,
        allowSafeCategoryFallback: force,
      );

      final now = DateTime.now();

      if (accepted.isEmpty) {
        final failed = base.copyWith(
          imagesFailedAt: now,
          imagesFailureReason: 'no_valid_images_after_filter',
          imageNeedsReview: true,
        );
        merge(failed);
        await _firebase.partialUpdate(id, {
          'imagesFailedAt': now.toIso8601String(),
          'imagesFailureReason': 'no_valid_images_after_filter',
          'imageNeedsReview': true,
          'updatedAt': now.toIso8601String(),
          'imageUpdateSource': imageUpdateSource,
        });
        return;
      }

      final mergedUrls = _mergeUrls(base.imageUrl, base.mediaUrls, accepted);
      final newHero = mergedUrls.isNotEmpty ? mergedUrls.first : base.imageUrl;
      final updated = base.copyWith(
        imageUrl: newHero,
        mediaUrls: mergedUrls,
        imagesRefreshedAt: now,
        imagePipelineVersion: ImageService.imagePipelineVersion,
        imagesAreFallback: force,
        imageNeedsReview: false,
        imagesFailureReason: '',
        imageRejectedReason: '',
      );

      merge(updated);

      await _firebase.partialUpdate(id, {
        'imageUrl': updated.imageUrl,
        'mediaUrls': updated.mediaUrls,
        'imagesRefreshedAt': now.toIso8601String(),
        'imagePipelineVersion': ImageService.imagePipelineVersion,
        'imagesAreFallback': updated.imagesAreFallback,
        'imageNeedsReview': false,
        'imagesFailureReason': '',
        'imageRejectedReason': '',
        'updatedAt': now.toIso8601String(),
        'imageUpdateSource': imageUpdateSource,
      });

      if (kDebugMode) {
        debugPrint(
          '[Images] savedToFirebase=true count=${updated.mediaUrls.length} place=${updated.name} fallback=${updated.imagesAreFallback}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PlaceRepository] enrichImages error: $e');
      }
      final now = DateTime.now();
      await _firebase.partialUpdate(id, {
        'imagesFailedAt': now.toIso8601String(),
        'imagesFailureReason': e.toString(),
        'updatedAt': now.toIso8601String(),
        'imageUpdateSource': imageUpdateSource,
      });
    } finally {
      _enrichingImages.remove(id);
    }
  }

  Future<void> enrichWikipedia(
    Landmark landmark, {
    bool force = false,
  }) async {
    final id = landmark.id.trim();
    if (id.isEmpty) return;
    if (_enrichingWiki.contains(id)) return;

    final cached = get(id);
    final base = cached ?? landmark;

    if (!force && !needsWikiRefresh(id)) return;

    _enrichingWiki.add(id);
    try {
      final wiki = await _wikipedia.search(base.name, cityName: base.city);
      if (wiki == null) return;

      final now = DateTime.now();
      final short = wiki.summary.trim().isNotEmpty
          ? wiki.summary.trim()
          : base.shortDescription;
      final full = wiki.fullText.trim().isNotEmpty
          ? wiki.fullText.trim()
          : base.fullDescription;

      final updated = base.copyWith(
        description: short,
        shortDescription: short,
        fullDescription: full,
        history: full.trim().isNotEmpty ? full : base.history,
        wikipediaUrl: wiki.pageUrl,
        wikiEnrichedAt: now,
      );

      merge(updated);

      await _firebase.enrichLandmarkWithWikipedia(
        docId: id,
        shortDescription: short,
        fullDescription: full,
        history: updated.history,
        wikipediaUrl: wiki.pageUrl,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PlaceRepository] enrichWikipedia error: $e');
      }
    } finally {
      _enrichingWiki.remove(id);
    }
  }

  Future<void> enrichNearby(
    Landmark landmark, {
    bool force = false,
  }) async {
    final id = landmark.id.trim();
    if (id.isEmpty) return;
    if (_enrichingNearby.contains(id)) return;

    final existing = get(id) ?? landmark;
    if (existing.lat == 0 || existing.lng == 0) return;
    if (!force && !needsNearbyRefresh(id)) return;

    _enrichingNearby.add(id);
    try {
      final existingNearby = existing.nearbyPlaces
          .map((e) => NearbyPlace.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      final result = await _nearby.getNearbyWithAutoRefresh(
        lat: existing.lat,
        lng: existing.lng,
        cityName: existing.city,
        existingPlaces: existingNearby,
        forceRefresh: force,
      );

      var resolved = result.places;

      if (resolved.isEmpty) {
        final all = await _firebase.getAllLandmarks();
        final fallback = all
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

      if (kDebugMode) {
        debugPrint('[Nearby] final result count = ${resolved.length}');
      }

      if (resolved.isEmpty) return;

      final updated = existing.copyWith(
        nearbyPlaces: resolved.map((p) => p.toJson()).toList(),
        nearbyUpdatedAt: result.refreshedAt,
      );

      merge(updated);

      await _firebase.partialUpdate(id, {
        'nearbyPlaces': updated.nearbyPlaces,
        'nearbyUpdatedAt': updated.nearbyUpdatedAt!.toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PlaceRepository] enrichNearby error: $e');
      }
    } finally {
      _enrichingNearby.remove(id);
    }
  }

  Stream<bool> favoriteStream(String placeId) => _firebase.favoriteStream(placeId);

  Stream<bool> visitedStream(String placeId) => _firebase.visitedStream(placeId);

  Future<void> toggleFavorite(Landmark place) => _firebase.toggleFavorite(place);

  Future<void> toggleVisited(Landmark place) => _firebase.toggleVisited(place);

  Future<List<Landmark>> getUserFavorites() => _firebase.getUserFavorites();

  Stream<List<Map<String, dynamic>>> reviewsStream(String placeId) =>
      _firebase.reviewsStream(placeId);

  Stream<double> averageRatingStream(String placeId) =>
      _firebase.averageRatingStream(placeId);

  Future<void> addReview({
    required String placeId,
    required double rating,
    required String comment,
  }) =>
      _firebase.addReview(
        placeId: placeId,
        rating: rating,
        comment: comment,
      );

  Future<void> deleteReview({
    required String placeId,
    required String userId,
  }) =>
      _firebase.deleteReview(
        placeId: placeId,
        userId: userId,
      );

  Stream<Map<String, String>> bookingLinksStream(String placeId) =>
      _firebase.bookingLinksStream(placeId);

  Future<List<City>> getCities() => _firebase.getCities();

  List<Landmark> _filterAndNormalize(List<Landmark> raw) {
    final deduped = <String, Landmark>{};

    for (final lm in raw) {
      if (lm.hidden || lm.isDuplicate || lm.invalidPlace) continue;
      if (lm.city.trim().isEmpty || lm.city.trim().toLowerCase() == 'egypt') {
        continue;
      }
      if (!PlaceCategoryNormalizer.isAllowed(lm.category, contextText: lm.name)) {
        continue;
      }

      final normalized = lm.copyWith(
        category: PlaceCategoryNormalizer.normalize(
          lm.category,
          contextText: lm.name,
        ),
      );

      final key =
          '${normalized.name.trim().toLowerCase()}|${normalized.city.trim().toLowerCase()}';

      deduped[key] = normalized;
    }

    return deduped.values.toList();
  }

  List<String> _mergeUrls(
    String mainUrl,
    List<String> existing,
    List<String> fetched,
  ) {
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

    for (final u in fetched) {
      add(u);
    }

    add(mainUrl);

    for (final u in existing) {
      add(u);
    }

    return result.take(6).toList();
  }

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
