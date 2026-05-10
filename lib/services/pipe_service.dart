// ============================================================
//  services/pipe_service.dart  (REBUILT)
//
//  Data pipeline: fetch → enrich → validate → save
//
//  Changes vs old version:
//  - Uses PlaceCategoryNormalizer (single source of truth)
//  - Faster: parallelizes image fetching where safe
//  - Refresh logic has proper TTL gates (not always-refresh)
//  - Better validation (no more empty place saves)
//  - Wikipedia refresh only when truly stale
// ============================================================

// ignore_for_file: avoid_print

import 'package:geoguide/core/place_category_normalizer.dart';
import 'package:geoguide/models.dart/createCity_model.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/services/Wikipedia%20service.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/services/image-service.dart';
import 'package:geoguide/services/landmark_cache.dart';
import 'package:geoguide/services/nearby-service.dart';
import 'package:geoguide/services/place-validate.dart';
import 'package:geoguide/services/places_service.dart';

typedef PipelineProgressCallback = void Function(String message);

class DataPipelineService {
  final GooglePlacesService _placesService;
  final ImageService _images;
  final WikipediaService _wikipedia;
  final FirebaseService _firebase;
  final NearbyService _nearby;
  final LandmarkCache _cache = LandmarkCache.instance;

  DataPipelineService({
    GooglePlacesService? googlePlaces,
    ImageService? images,
    WikipediaService? wikipedia,
    FirebaseService? firebase,
    NearbyService? nearby,
  })  : _placesService = googlePlaces ?? GooglePlacesService(),
        _images = images ?? ImageService(),
        _wikipedia = wikipedia ?? WikipediaService(),
        _firebase = firebase ?? FirebaseService(),
        _nearby = nearby ?? NearbyService();

  // ════════════════════════════════════════════════════════
  //  MAIN ENTRY POINT
  // ════════════════════════════════════════════════════════

  Future<List<Landmark>> fetchOrLoadLandmarks(
    City city, {
    bool forceRefresh = false,
    PipelineProgressCallback? onProgress,
  }) async {
    void notify(String msg) => onProgress?.call(msg);

    if (!forceRefresh) {
      notify('Loading "${city.name}" from database…');

      final cachedById = await _firebase.getLandmarksByCity(city.id);
      final allCached = await _firebase.getAllLandmarks();
      final cityNameLower = city.name.trim().toLowerCase();

      // Some generated/search documents may have an empty or old cityId,
      // but still have the correct city/address. Use both cityId and city name
      // before deciding that the city needs a full external generation.
      final cachedByName = allCached.where((lm) {
        final lmCity = lm.city.trim().toLowerCase();
        final lmAddress = lm.address.trim().toLowerCase();
        return lmCity == cityNameLower ||
            lmCity.contains(cityNameLower) ||
            cityNameLower.contains(lmCity) ||
            lmAddress.contains(cityNameLower);
      }).toList();

      final cached = _filterAndDedup([
        ...cachedById,
        ...cachedByName,
      ], city.name);

      final valid = _filterValid(cached);
      if (valid.isNotEmpty) {
        for (final lm in valid) {
          if (!_cache.has(lm.id)) _cache.put(lm);
        }

        // Keep enrichment non-blocking. If you want zero background API calls
        // when cached data exists, comment this line.
        _backgroundRefresh(valid, city, notify);

        return valid;
      }
    }

    // ── Full pipeline ──────────────────────────────────────
    notify('Fetching places for "${city.name}"…');

    List<Map<String, dynamic>> rawPlaces = [];
    try {
      rawPlaces = await _placesService.fetchAllCategoriesForCity(
        lat: city.lat,
        lng: city.lng,
        cityId: city.id,
        cityName: city.name,
      );
    } catch (e) {
      notify('Error fetching places: $e');
    }

    if (rawPlaces.isEmpty) {
      notify('No places found for "${city.name}"');
      return [];
    }

    notify('Processing ${rawPlaces.length} places…');

    // Convert to Landmark objects
    final landmarks = <Landmark>[];
    for (final raw in rawPlaces) {
      try {
        final lm = _placesService.fromGoogleResult(
          raw,
          cityId: city.id,
          cityName: city.name,
        );
        if (_isValidForCity(lm, city.name)) {
          landmarks.add(lm);
        }
      } catch (_) {}
    }

    if (landmarks.isEmpty) {
      notify('No valid places for "${city.name}"');
      return [];
    }

    // ── Images (parallelized in batches of 4) ─────────────
    notify('Fetching images…');
    final withImages = await _fetchImagesParallel(landmarks, city.name);

    // ── Wikipedia ─────────────────────────────────────────
    notify('Enriching descriptions…');
    final enriched = await _enrichWithWikipedia(withImages, city.name);

    // ── Validate and deduplicate ──────────────────────────
    final valid = _filterAndDedup(enriched, city.name);

    if (valid.isEmpty) {
      notify('No valid places survived validation.');
      return [];
    }

    // ── Save core places first ─────────────────────────────
    // Important: do NOT wait for nearby enrichment before saving.
    // This makes selecting a city fast and guarantees new places are stored
    // even if Overpass is slow, rate-limited, or unavailable.
    notify('Saving ${valid.length} core places to database…');
    try {
      await _firebase.saveLandmarks(valid);
      for (final lm in valid) {
        _cache.merge(lm);
      }
    } catch (e) {
      notify('Core save error: $e');
    }

    // ── Nearby preload in the background ───────────────────
    // Nearby is expensive; keep it non-blocking so the Home screen updates
    // quickly. PlaceInfoScreen will still refresh a specific place on open.
    _preloadNearbyInBackground(valid, notify);

    notify('Done! ${valid.length} places ready for "${city.name}"');

    final result = await _firebase.getLandmarksByCity(city.id);
    final validResult = _filterValid(result);
    for (final lm in validResult) {
      _cache.put(lm);
    }
    return validResult;
  }

  // ════════════════════════════════════════════════════════
  //  BACKGROUND REFRESH (non-blocking)
  // ════════════════════════════════════════════════════════

  Future<void> _backgroundRefresh(
    List<Landmark> cached,
    City city,
    PipelineProgressCallback notify,
  ) async {
    // This runs async — errors are swallowed
    try {
      bool changed = false;
      final updated = <Landmark>[];

      for (final lm in cached) {
        Landmark current = lm;
        bool dirty = false;

        // Images refresh (14-day TTL)
        if (_cache.needsImageRefresh(lm.id)) {
          final fetched = await _images.fetchImages(
            current.name,
            cityName: current.city.trim().isNotEmpty ? current.city : city.name,
            category: current.category,
            count: 6,
            excludeUrls: current.mediaUrls,
          );

          if (fetched.isNotEmpty) {
            final merged = _mergeUrls(
                current.imageUrl, current.mediaUrls, fetched);
            if (merged.length > current.mediaUrls.length ||
                (current.imageUrl.trim().isEmpty && merged.isNotEmpty)) {
              current = current.copyWith(
                imageUrl:
                    merged.isNotEmpty ? merged.first : current.imageUrl,
                mediaUrls: merged,
                imagesRefreshedAt: DateTime.now(),
                imagePipelineVersion: ImageService.imagePipelineVersion,
                imagesAreFallback: false,
              );
              dirty = true;
            }
          }
        }

        // Wikipedia refresh (30-day TTL)
        if (_cache.needsWikiRefresh(lm.id)) {
          try {
            final wiki = await _wikipedia.search(
              current.name,
              cityName: city.name,
            );

            if (wiki != null &&
                PlaceValidator.isValidWikipediaResult(
                  title: wiki.title,
                  extract: wiki.fullText,
                  description: wiki.summary,
                )) {
              final history =
                  _wikipedia.extractHistorySection(wiki.fullText).trim();
              current = current.copyWith(
                shortDescription: wiki.summary.trim().isNotEmpty
                    ? wiki.summary.trim()
                    : current.shortDescription,
                fullDescription: wiki.fullText.trim().isNotEmpty
                    ? wiki.fullText.trim()
                    : current.fullDescription,
                history: history.isNotEmpty
                    ? history
                    : (wiki.fullText.isNotEmpty
                        ? wiki.fullText
                        : current.history),
                wikipediaUrl: wiki.pageUrl,
                wikiEnrichedAt: DateTime.now(),
              );
              dirty = true;
            }
          } catch (_) {}
        }

        if (dirty) changed = true;
        updated.add(current);
        if (dirty) _cache.merge(current);
      }

      if (changed) {
        await _firebase.saveLandmarks(updated);
      }
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════
  //  PIPELINE STEPS
  // ════════════════════════════════════════════════════════

  Future<List<Landmark>> _fetchImagesParallel(
    List<Landmark> landmarks,
    String cityName,
  ) async {
    const batchSize = 4;
    final result = <Landmark>[];

    for (int i = 0; i < landmarks.length; i += batchSize) {
      final batch = landmarks.sublist(
        i,
        (i + batchSize).clamp(0, landmarks.length),
      );

      final fetched = await Future.wait(
        batch.map((lm) async {
          try {
            final urls = await _images.fetchImages(
              lm.name,
              cityName: lm.city.trim().isNotEmpty ? lm.city : cityName,
              category: lm.category,
              count: 6,
              excludeUrls: lm.mediaUrls,
            );

            if (urls.isEmpty) return lm;

            final merged = _mergeUrls(lm.imageUrl, lm.mediaUrls, urls);
            return lm.copyWith(
              imageUrl: merged.isNotEmpty ? merged.first : lm.imageUrl,
              mediaUrls: merged,
              imagesRefreshedAt: DateTime.now(),
              imagePipelineVersion: ImageService.imagePipelineVersion,
              imagesAreFallback: false,
            );
          } catch (_) {
            return lm;
          }
        }),
      );

      result.addAll(fetched);
    }

    return result;
  }

  Future<List<Landmark>> _enrichWithWikipedia(
    List<Landmark> landmarks,
    String cityName,
  ) async {
    final result = <Landmark>[];

    for (final lm in landmarks) {
      Landmark current = lm;

      try {
        final wiki =
            await _wikipedia.search(lm.name, cityName: cityName);

        if (wiki != null &&
            PlaceValidator.isValidWikipediaResult(
              title: wiki.title,
              extract: wiki.fullText,
              description: wiki.summary,
            )) {
          final history =
              _wikipedia.extractHistorySection(wiki.fullText).trim();

          final shortDesc = wiki.summary.trim().isNotEmpty
              ? wiki.summary.trim()
              : lm.shortDescription;
          final fullDesc = wiki.fullText.trim().isNotEmpty
              ? wiki.fullText.trim()
              : lm.fullDescription;

          current = lm.copyWith(
            description: shortDesc,
            shortDescription: shortDesc,
            fullDescription: fullDesc,
            history: history.isNotEmpty ? history : fullDesc,
            wikipediaUrl: wiki.pageUrl,
            wikiEnrichedAt: DateTime.now(),
          );
        } else {
          // Generate fallback description
          if (current.shortDescription.trim().isEmpty) {
            final fallback = _fallbackDescription(lm);
            current = lm.copyWith(
              description: fallback,
              shortDescription: fallback,
              fullDescription: fallback,
            );
          }
        }
      } catch (_) {
        if (current.shortDescription.trim().isEmpty) {
          final fallback = _fallbackDescription(lm);
          current = lm.copyWith(
            description: fallback,
            shortDescription: fallback,
          );
        }
      }

      result.add(current);
    }

    return result;
  }

  Future<void> _preloadNearbyInBackground(
    List<Landmark> landmarks,
    PipelineProgressCallback notify,
  ) async {
    try {
      final candidates = landmarks
          .where((lm) => lm.id.trim().isNotEmpty)
          .where((lm) => lm.lat != 0 && lm.lng != 0)
          .take(12)
          .toList();

      if (candidates.isEmpty) return;

      notify('Preloading nearby for ${candidates.length} places in background…');

      for (final lm in candidates) {
        try {
          final existing = lm.nearbyPlaces
              .map((e) => NearbyPlace.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList();

          final nearbyResult = await _nearby.getNearbyWithAutoRefresh(
            lat: lm.lat,
            lng: lm.lng,
            existingPlaces: existing,
            lastFetchedAt: lm.nearbyUpdatedAt,
            categories: const [
              'hotel',
              'restaurant',
              'cafe',
              'tourist',
              'outing',
            ],
            limit: 18, cityName: '',
          );

          if (nearbyResult.places.isEmpty) continue;

          final updated = lm.copyWith(
            nearbyPlaces: nearbyResult.places.map((p) => p.toJson()).toList(),
            nearbyUpdatedAt: nearbyResult.refreshedAt ?? DateTime.now(),
          );

          _cache.merge(updated);
          await _firebase.partialUpdate(updated.id, {
            'nearbyPlaces': updated.nearbyPlaces,
            'nearbyUpdatedAt': updated.nearbyUpdatedAt!.toIso8601String(),
          });
        } catch (e) {
          print('[Pipeline] nearby preload error for ${lm.name}: $e');
        }
      }
    } catch (e) {
      print('[Pipeline] nearby background preload error: $e');
    }
  }

  // ════════════════════════════════════════════════════════
  //  VALIDATION / FILTERING
  // ════════════════════════════════════════════════════════

  List<Landmark> _filterValid(List<Landmark> items) {
    final seen = <String>{};
    final result = <Landmark>[];

    for (final lm in items) {
      if (lm.id.trim().isEmpty) continue;
      if (lm.name.trim().isEmpty) continue;
      if (lm.city.trim().isEmpty || lm.city.toLowerCase() == 'egypt') {
        continue;
      }

      final normCat = PlaceCategoryNormalizer.normalize(
        lm.category,
        contextText: '${lm.name} ${lm.description}',
      );
      if (!PlaceCategoryNormalizer.allowed.contains(normCat)) continue;

      final key =
          '${lm.name.trim().toLowerCase()}|${lm.city.trim().toLowerCase()}';
      if (!seen.add(key)) continue;

      result.add(lm.copyWith(category: normCat));
    }

    return result;
  }

  List<Landmark> _filterAndDedup(List<Landmark> items, String cityName) {
    final seen = <String>{};
    final result = <Landmark>[];

    for (final lm in items) {
      if (!_isValidForCity(lm, cityName)) continue;
      if (!PlaceValidator.isValidPlace(
        name: lm.name,
        description:
            '${lm.description} ${lm.shortDescription} ${lm.fullDescription}',
        category: lm.category,
        city: lm.city,
      )) {
        continue;
      }

      final normCat = PlaceCategoryNormalizer.normalize(
        lm.category,
        contextText: '${lm.name} ${lm.description}',
      );
      if (!PlaceCategoryNormalizer.allowed.contains(normCat)) continue;

      final key =
          '${lm.name.trim().toLowerCase()}|${lm.city.trim().toLowerCase()}';
      if (!seen.add(key)) continue;

      result.add(lm.copyWith(category: normCat));
    }

    return result;
  }

  bool _isValidForCity(Landmark lm, String cityName) {
    if (lm.name.trim().isEmpty) return false;
    if (lm.city.trim().isEmpty) return false;

    final lmCity = lm.city.trim().toLowerCase();
    final hint = cityName.trim().toLowerCase();

    return lmCity == hint ||
        lmCity.contains(hint) ||
        hint.contains(lmCity);
  }

  // ════════════════════════════════════════════════════════
  //  HELPERS
  // ════════════════════════════════════════════════════════

  List<String> _mergeUrls(
    String existingMain,
    List<String> existingList,
    List<String> newUrls,
  ) {
    final seen = <String>{};
    final result = <String>[];

    void add(String url) {
      final clean = url.trim();
      if (clean.isNotEmpty &&
          (clean.startsWith('http://') || clean.startsWith('https://')) &&
          seen.add(clean)) {
        result.add(clean);
      }
    }

    // New verified images should be first. Old images may be from an older
    // pipeline version and must not keep the UI stuck on a placeholder.
    for (final u in newUrls) add(u);
    if (existingMain.trim().isNotEmpty) add(existingMain);
    for (final u in existingList) add(u);

    return result.take(6).toList();
  }

  String _fallbackDescription(Landmark lm) {
    final catLabel = {
          'tourist': 'tourist attraction',
          'restaurant': 'restaurant',
          'hotel': 'hotel',
          'cafe': 'cafe',
          'outing': 'recreational place',
        }[PlaceCategoryNormalizer.normalize(lm.category)] ??
        'place';

    return '${lm.name} is a $catLabel in ${lm.city}, Egypt.';
  }
}