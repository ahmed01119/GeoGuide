// ============================================================
//  place_search_pipeline.dart
//
//  Shared helpers for the GeoGuide search → Firebase → enrich flow.
//
//  Search pipeline (high level):
//  1) normalizeSearchQuery / resolveOfficialPlaceName — clean user text
//     and pick API-friendly names for image / OSM / Wikipedia calls.
//  2) SearchEngine loads Firebase index first, ranks, then optionally
//     generates from external providers.
//  3) classifyPlaceCategory / isAllowedCategory — only the five app
//     categories (tourist, hotel, restaurant, cafe, outing) may persist.
//  4) buildStablePlaceId — deterministic fingerprint for logs / dedupe.
//  5) validatePlaceForFirebaseSave — block incomplete or junk rows.
//  6) isLikelyDuplicate / coordinatesNear — merge duplicates before save.
//  7) Throttle windows (imagesRefreshedAt, nearbyUpdatedAt) avoid API spam.
// ============================================================

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:geoguide/core/canonical_city_resolver.dart';
import 'package:geoguide/core/place_category_normalizer.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/services/firebase_nearby_cache_extension.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/services/image-service.dart';

/// Where a search result row came from (debugging / analytics).
enum PlaceResultSource {
  fromFirebase,
  generatedBySearch,
  refreshedFromApi,
}

class PlaceSearchPipeline {
  PlaceSearchPipeline._();

  /// Skip automatic image / heavy detail refresh if refreshed within this window.
  static const Duration imageRefreshMinInterval = Duration(days: 7);

  /// Skip automatic nearby refresh if updated within this window.
  static const Duration nearbyRefreshMinInterval = Duration(hours: 24);

  /// Minimum distance (meters) to treat two places as different when names differ.
  static const double duplicateDistanceMeters = 120;

  // ── Normalization & naming ─────────────────────────────────

  /// Collapses whitespace, trims, and unifies common Arabic variants for search keys.
  /// Also maps Eastern Arabic numerals to Latin digits (general, not query-specific).
  static String normalizeSearchQuery(String raw) {
    return _normalizeKey(_expandNumeralsAndCommonNoise(raw));
  }

  /// Extra orthography pass before [_normalizeKey] (digits, thin spaces, etc.).
  static String _expandNumeralsAndCommonNoise(String raw) {
    var s = raw.trim().replaceAll('\u200f', '').replaceAll('\u200e', '');
    const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    for (var i = 0; i < ar.length; i++) {
      s = s.replaceAll(ar[i], en[i]);
    }
    return s;
  }

  static String _normalizeKey(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[إأآا]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Detects an Egyptian city/governorate mentioned or implied in free text.
  /// Uses a reusable alias table + optional trailing "in/near/around …" clause.
  static String? cityFromNormalizedText(String normalizedKey) {
    final n = normalizedKey;
    if (n.isEmpty) return null;
    return CanonicalCityResolver.cityNameFromNormalizedSearchKey(n);
  }

  static String? _cityFromLocationClause(String normalizedKey) {
    final n = normalizedKey;
    if (n.isEmpty) return null;
    final re = RegExp(
      r'\b(in|near|around|at|داخل|في|عند|ب)\s+([a-z0-9\u0600-\u06FF\s]+)$',
    );
    final m = re.firstMatch(n);
    if (m == null) return null;
    final tail = (m.group(2) ?? '').trim();
    if (tail.isEmpty) return null;
    return cityFromNormalizedText(tail);
  }

  /// Detects an Egyptian city/governorate explicitly mentioned in the user query.
  /// Longer aliases are matched first so "Sharm El Sheikh" beats "Sharm".
  static String? extractCityIntentFromQuery(String raw) {
    final expanded = _expandNumeralsAndCommonNoise(raw);
    final n = _normalizeKey(expanded);
    if (n.isEmpty) return null;

    final fromBody = cityFromNormalizedText(n);
    if (fromBody != null) return fromBody;

    return _cityFromLocationClause(n);
  }

  /// Drops search rows that do not share enough tokens with the query / city intent.
  static bool passesSearchRelevance(
    Landmark lm,
    String rawQuery, {
    String? cityIntent,
  }) {
    final q = _normalizeKey(rawQuery);
    if (q.isEmpty) return true;

    final tokens = q
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2)
        .where((t) => !_isStopword(t))
        .toList();
    if (tokens.isEmpty) return true;

    final hay = _normalizeKey(
      '${lm.name} ${lm.displayName} ${lm.normalizedName} ${lm.aliases.join(' ')} '
      '${lm.city} ${lm.address} ${lm.shortDescription}',
    );

    var hits = 0;
    for (final t in tokens) {
      if (hay.contains(t)) hits++;
    }

    final required = math.max(1, (tokens.length * 0.51).ceil());
    if (hits < required) return false;

    if (cityIntent != null && cityIntent.trim().isNotEmpty) {
      final ci = _normalizeKey(cityIntent);
      final lc = _normalizeKey(lm.city);
      final addr = _normalizeKey(lm.address);
      if (ci.isNotEmpty &&
          !lc.contains(ci) &&
          !hay.contains(ci) &&
          !addr.contains(ci)) {
        return false;
      }
    }
    return true;
  }

  static bool _isStopword(String t) {
    const s = {
      'the', 'and', 'for', 'with', 'from', 'near', 'best', 'top', 'place',
      'places', 'area', 'city', 'egypt', 'في', 'من', 'على', 'عن', 'أفضل',
    };
    return s.contains(t);
  }

  /// Rejects Franco-garbage strings that should never hit stock image APIs.
  static bool isBrokenTransliterationName(String name) {
    final raw = name.trim();
    if (raw.isEmpty) return true;
    final n = raw.replaceAll(RegExp(r'\s+'), ' ');

    final badPatterns = [
      RegExp(r'AlMuseum|Qaaa|Almq|Mmnwn', caseSensitive: false),
      RegExp(r'[bcdfghjklmnpqrstvwxyz]{7,}', caseSensitive: false),
    ];
    for (final re in badPatterns) {
      if (re.hasMatch(n)) return true;
    }

    final letters = n.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (letters.length >= 6) {
      final vowels = letters.split('').where((c) => 'aeiouAEIOU'.contains(c)).length;
      if (vowels / letters.length < 0.12) return true;
    }
    return false;
  }

  /// Visitor-oriented outing: parks, beaches, malls, entertainment, etc.
  /// Rejects generic streets, schools, offices, and other non-visitor POIs.
  static bool isVerifiedVisitorOutingCandidate({
    required String name,
    required String displayName,
    required String osmClass,
    required String osmType,
  }) {
    final t = _normalizeKey('$name $displayName $osmClass $osmType');
    if (t.isEmpty) return false;

    final negative = RegExp(
      r'\b(school|schools|university|college|academy|kindergarten|hospital|clinics?|medical|pharmacy|dentist|veterinary|police|embassy|consulate|ministry|government|courthouse|municipal|office|offices|warehouse|factory|residential|apartment|housing|estate|compound|bank branch|atm only|parking|garage|workshop|clinic|مسجد\s+سكني|مدرسه|جامعه|مستشفي|مستشفى|عياده|شرطه|وزاره|وزارة|محكمه|مكتب|مصنع|سكني)\b',
    );
    if (negative.hasMatch(t)) return false;

    final positive = RegExp(
      r'\b(park|garden|gardens|playground|beach|beaches|coast|seafront|promenade|corniche|waterfront|mall|shopping|cinema|theatre|theater|zoo|aquarium|stadium|amusement|entertainment|nightlife|viewpoint|lookout|plaza|square|market|souk|bazaar|marina|harbor|harbour|oasis|leisure|recreation|boardwalk|ferris|theme\s*park|water\s*park|escape\s*room|bowling|ice\s*rink)\b',
    ).hasMatch(t) ||
        RegExp(
          r'(حديقه|حدائق|شاطئ|شواطئ|كورنيش|مول|سينما|ملاهي|مارينا|سوق|خان|ترفيه|فسحه|خروجه|منطقه ترفيهيه)',
        ).hasMatch(t);

    final osmLeisure = RegExp(
      r'\b(park|garden|playground|beach|nature_reserve|water_park|stadium|sports_centre|fitness_centre|theme_park|marina|viewpoint|attraction|picnic_site|dog_park|miniature_golf|ice_rink|bowling_alley|escape_game|dance|nightclub|arts_centre|cinema)\b',
    ).hasMatch(_normalizeKey('$osmClass $osmType'));

    return positive || osmLeisure;
  }

  /// Same as [isVerifiedVisitorOutingCandidate] using fields available on [Landmark].
  static bool isVerifiedVisitorOutingLandmark(Landmark lm) {
    final src = lm.sources ?? const <String, dynamic>{};
    return isVerifiedVisitorOutingCandidate(
      name: lm.name,
      displayName: '${lm.displayName} ${lm.shortDescription} ${lm.address}',
      osmClass: (src['osm_class'] ?? src['class'] ?? '').toString(),
      osmType: (src['osm_type'] ?? src['type'] ?? '').toString(),
    );
  }

  static String? resolveOfficialPlaceName(String query) {
    final q = _normalizeKey(query);
    if (q.isEmpty) return null;

    const Map<String, String> francoAndAliases = {
      'ahram': 'Pyramids of Giza',
      'ahramat': 'Pyramids of Giza',
      'al ahram': 'Pyramids of Giza',
      'el ahram': 'Pyramids of Giza',
      'ahramat giza': 'Pyramids of Giza',
      'giza pyramids': 'Pyramids of Giza',
      'abu hol': 'Great Sphinx of Giza',
      'abo hol': 'Great Sphinx of Giza',
      'khan elkhalili': 'Khan el-Khalili',
      'khan el khalili': 'Khan el-Khalili',
      'khan al khalili': 'Khan el-Khalili',
      'gena': 'Luxor',
      'loxor': 'Luxor',
      'loksor': 'Luxor',
      'aswan': 'Aswan',
      'asone': 'Aswan',
      'skndrya': 'Alexandria',
      'iskndrya': 'Alexandria',
    };

    if (francoAndAliases.containsKey(q)) return francoAndAliases[q];

    for (final e in francoAndAliases.entries) {
      if (q.contains(e.key) || e.key.contains(q)) return e.value;
    }

    return null;
  }

  static String normalizedNameKey(Landmark lm) {
    final n = lm.normalizedName.trim();
    if (n.isNotEmpty) return _normalizeKey(n);
    return _normalizeKey(lm.name);
  }

  /// English / official string used for ImageService, OSM, Wikipedia.
  static String apiSearchName(Landmark lm) {
    if (isBrokenTransliterationName(lm.name)) {
      final r = resolveOfficialPlaceName(lm.name) ??
          resolveOfficialPlaceName(lm.displayName);
      if (r != null && r.trim().isNotEmpty && !isBrokenTransliterationName(r)) {
        return r.trim();
      }
    }
    final n = lm.normalizedName.trim();
    if (n.isNotEmpty) return n;
    final resolved = resolveOfficialPlaceName(lm.name);
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return lm.name.trim();
  }

  /// User-facing title: Arabic/local display when provided, else [Landmark.name].
  static String displayTitle(Landmark lm) {
    final d = lm.displayName.trim();
    if (d.isNotEmpty) return d;
    return lm.name.trim();
  }

  // ── Categories ─────────────────────────────────────────────

  static String classifyPlaceCategory(String raw, {String contextText = ''}) {
    return PlaceCategoryNormalizer.normalize(raw, contextText: contextText);
  }

  static bool isAllowedCategory(String raw, {String contextText = ''}) {
    return PlaceCategoryNormalizer.isAllowed(raw, contextText: contextText);
  }

  // ── IDs & validation ─────────────────────────────────────

  static String buildStablePlaceId(String name, String city, String category) {
    return '${_normalizeKey(name)}|${_normalizeKey(city)}|${classifyPlaceCategory(category, contextText: name)}';
  }

  static bool validatePlaceForFirebaseSave(Landmark lm) {
    if (lm.name.trim().isEmpty) return false;
    final cat = classifyPlaceCategory(lm.category, contextText: lm.name);
    if (!PlaceCategoryNormalizer.allowed.contains(cat)) return false;
    final cityLower = lm.city.trim().toLowerCase();
    final hasCity =
        lm.city.trim().isNotEmpty && cityLower != 'egypt';
    final hasCoords = lm.lat != 0 && lm.lng != 0;
    if (!hasCity && !hasCoords) return false;
    return true;
  }

  static bool coordinatesNear(double lat1, double lng1, double lat2, double lng2,
      {double meters = duplicateDistanceMeters}) {
    if (lat1 == 0 || lng1 == 0 || lat2 == 0 || lng2 == 0) return false;
    const earth = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final s1 = math.sin(dLat / 2);
    final s2 = math.sin(dLng / 2);
    final a = s1 * s1 +
        math.cos(_degToRad(lat1)) * math.cos(_degToRad(lat2)) * s2 * s2;
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earth * c <= meters;
  }

  static double _degToRad(double d) => d * math.pi / 180.0;

  static bool isLikelyDuplicate(Landmark a, Landmark b) {
    if (a.id.isNotEmpty && b.id.isNotEmpty && a.id == b.id) return true;
    final ca = classifyPlaceCategory(a.category, contextText: a.name);
    final cb = classifyPlaceCategory(b.category, contextText: b.name);
    if (ca != cb) return false;
    final na = normalizedNameKey(a);
    final nb = normalizedNameKey(b);
    if (na.isNotEmpty && nb.isNotEmpty && na == nb) {
      final cityA = _normalizeKey(a.city);
      final cityB = _normalizeKey(b.city);
      if (cityA.isNotEmpty && cityB.isNotEmpty && cityA == cityB) return true;
    }
    if (coordinatesNear(a.lat, a.lng, b.lat, b.lng) &&
        _normalizeKey(a.name) == _normalizeKey(b.name)) {
      return true;
    }
    return false;
  }

  /// True when [a] and [b] are the same real-world place for image de-duplication:
  /// same doc, [isLikelyDuplicate], or same name/alias family in the same city context.
  /// Used so alias/merge rows can share Wikimedia URLs without being stripped as unrelated.
  static bool isSameLogicalPlaceForImageSharing(Landmark a, Landmark b) {
    if (a.id.isNotEmpty && b.id.isNotEmpty && a.id == b.id) return true;
    if (isLikelyDuplicate(a, b)) return true;

    bool nameFamilyOverlap() {
      final na = normalizedNameKey(a);
      final nb = normalizedNameKey(b);
      if (na.isNotEmpty && nb.isNotEmpty && na == nb) return true;
      final keysA = <String>{
        _normalizeKey(a.name),
        ...a.aliases.map(_normalizeKey),
      }..removeWhere((e) => e.isEmpty);
      final keysB = <String>{
        _normalizeKey(b.name),
        ...b.aliases.map(_normalizeKey),
      }..removeWhere((e) => e.isEmpty);
      return keysA.any(keysB.contains);
    }

    if (!nameFamilyOverlap()) return false;

    final cida = a.cityId.trim();
    final cidb = b.cityId.trim();
    if (cida.isNotEmpty && cidb.isNotEmpty) return cida == cidb;

    final ca = _normalizeKey(a.city);
    final cb = _normalizeKey(b.city);
    if (ca.isNotEmpty && cb.isNotEmpty) return ca == cb;

    return coordinatesNear(a.lat, a.lng, b.lat, b.lng);
  }

  // ── Throttle ───────────────────────────────────────────────

  static bool shouldRefreshImages(DateTime? imagesRefreshedAt) {
    if (imagesRefreshedAt == null) return true;
    return DateTime.now().difference(imagesRefreshedAt) > imageRefreshMinInterval;
  }

  static bool shouldRefreshNearby(DateTime? nearbyUpdatedAt) {
    if (nearbyUpdatedAt == null) return true;
    return DateTime.now().difference(nearbyUpdatedAt) > nearbyRefreshMinInterval;
  }

  // ── Prepare landmark for Firestore ─────────────────────────

  /// Fills naming helpers, aliases, and flags before [FirebaseService.saveLandmark].
  static Landmark prepareLandmarkForPersist(
    Landmark lm, {
    required String rawQuery,
    bool generatedBySearch = false,
  }) {
    final originalName = lm.name.trim();
    final officialFromQuery =
        resolveOfficialPlaceName(rawQuery);
    final officialFromName =
        resolveOfficialPlaceName(originalName);
    final official = officialFromQuery ?? officialFromName;

    var nextName = originalName;
    var display = lm.displayName.trim();
    final aliasSet = <String>{
      ...lm.aliases,
      if (rawQuery.trim().isNotEmpty) rawQuery.trim(),
      if (originalName.isNotEmpty) originalName,
    };

    if (official != null && official.isNotEmpty) {
      nextName = official;
      aliasSet.add(official);
      if (_normalizeKey(official) != _normalizeKey(originalName) &&
          display.isEmpty) {
        display = originalName;
      }
    }

    final normalized = _normalizeKey(nextName);

    return lm.copyWith(
      name: nextName,
      displayName: display,
      normalizedName: normalized,
      aliases: aliasSet.toList(),
      category: classifyPlaceCategory(lm.category, contextText: nextName),
      generatedBySearch: generatedBySearch || lm.generatedBySearch,
      updatedAt: DateTime.now(),
    );
  }

  static void debugLog(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[PlaceSearchPipeline] $message');
    }
  }

  /// Persists a generated landmark after validation (wrapper around [FirebaseService.saveLandmark]).
  static Future<String?> saveGeneratedPlaceToFirebase(
    FirebaseService firebase,
    Landmark place,
  ) async {
    if (!validatePlaceForFirebaseSave(place)) return null;
    try {
      return await firebase.saveLandmark(place);
    } catch (e) {
      debugLog('saveGeneratedPlaceToFirebase failed: $e');
      return null;
    }
  }

  /// Writes merged nearby rows under `landmarks/{parentPlaceId}`.
  static Future<void> saveNearbyPlacesForPlace(
    FirebaseService firebase, {
    required String parentPlaceId,
    required List<Map<String, dynamic>> nearbyPlaces,
  }) {
    return firebase.saveNearbyPlacesForLandmark(
      placeId: parentPlaceId,
      nearbyPlaces: nearbyPlaces,
    );
  }

  /// Fetches images using [Landmark.apiSearchName] and merges into Firestore when URLs exist.
  static Future<void> enrichPlaceWithImagesAndDetails({
    required Landmark place,
    required ImageService images,
    required FirebaseService firebase,
  }) async {
    final id = place.id.trim();
    if (id.isEmpty) return;
    if (!shouldRefreshImages(place.imagesRefreshedAt) &&
        place.imageUrl.trim().isNotEmpty) {
      return;
    }
    try {
      final fetchedRaw = await images.fetchImages(
        place.apiSearchName,
        cityName: place.city,
        category: place.category,
        count: 6,
        excludeUrls: [place.imageUrl, ...place.mediaUrls],
      );
      final metaBase =
          '${place.name} ${place.city} ${PlaceCategoryNormalizer.normalize(place.category, contextText: place.name)}';
      final fetched = await images.filterPersistableImageUrls(
        urls: fetchedRaw,
        placeName: place.name,
        cityName: place.city,
        category: place.category,
        metaTextBase: metaBase,
        findOwnersForImageUrl: firebase.findLandmarkIdsWithImageUrl,
        excludeLandmarkId: id,
        allowDuplicateOwnersForSamePlace: (url, ownerIds) =>
            firebase.imageOwnersAllowHeroSharingWithSubject(place, ownerIds),
      );
      if (fetched.isEmpty) return;
      final merged = <String>{place.imageUrl, ...place.mediaUrls, ...fetched}
          .map((e) => e.trim())
          .where((e) => e.startsWith('http'))
          .toList();
      if (merged.isEmpty) return;
      await firebase.partialUpdate(id, {
        'imageUrl': merged.first,
        'mediaUrls': merged.take(6).toList(),
        'imagesRefreshedAt': DateTime.now().toIso8601String(),
        'imagePipelineVersion': ImageService.imagePipelineVersion,
        'imagesAreFallback': false,
        'imageNeedsReview': false,
        'imageRejectedReason': '',
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugLog('enrichPlaceWithImagesAndDetails failed: $e');
    }
  }
}

extension LandmarkSearchApiX on Landmark {
  /// String passed to ImageService / remote search APIs.
  String get apiSearchName => PlaceSearchPipeline.apiSearchName(this);
}
