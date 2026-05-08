// ============================================================
//  services/landmark_cache.dart
//
//  Production memory cache for Landmark objects.
//  - TTL-aware freshness checks
//  - Smart merge (never downgrades)
//  - Per-landmark change streams for live UI updates
//  - Thread-safe singleton
// ============================================================

import 'dart:async';
import 'package:geoguide/models.dart/landmark_model.dart';

class LandmarkCache {
  LandmarkCache._();
  static final LandmarkCache instance = LandmarkCache._();

  // ── Storage ───────────────────────────────────────────────
  final Map<String, _Entry> _store = {};

  // ── Stream controllers per place ─────────────────────────
  final Map<String, StreamController<Landmark>> _controllers = {};

  // ── TTLs ──────────────────────────────────────────────────
  static const Duration _freshTtl = Duration(minutes: 15);
  static const Duration _imageTtl = Duration(days: 14);
  static const Duration _wikiTtl = Duration(days: 30);
  static const Duration _nearbyTtl = Duration(hours: 6);

  // ════════════════════════════════════════════════════════
  //  WRITE
  // ════════════════════════════════════════════════════════

  /// Put a landmark into the cache unconditionally.
  void put(Landmark landmark) {
    if (landmark.id.trim().isEmpty) return;
    _store[landmark.id] = _Entry(landmark: landmark, cachedAt: DateTime.now());
    _notify(landmark);
  }

  /// Merge incoming data, always keeping the richer version per field.
  void merge(Landmark incoming) {
    if (incoming.id.trim().isEmpty) return;

    final existing = _store[incoming.id]?.landmark;
    if (existing == null) {
      put(incoming);
      return;
    }

    final merged = _mergeTwo(existing, incoming);
    put(merged);
  }

  // ════════════════════════════════════════════════════════
  //  READ
  // ════════════════════════════════════════════════════════

  /// Returns cached landmark, or null if not present.
  Landmark? get(String id) => _store[id]?.landmark;

  /// Returns cached landmark only if it is still within [_freshTtl].
  Landmark? getFresh(String id) {
    final entry = _store[id];
    if (entry == null) return null;
    if (_isExpired(entry.cachedAt, _freshTtl)) return null;
    return entry.landmark;
  }

  bool has(String id) => _store.containsKey(id);

  // ════════════════════════════════════════════════════════
  //  STREAMS
  // ════════════════════════════════════════════════════════

  /// Returns a stream that emits whenever the landmark with [id] changes.
  Stream<Landmark> stream(String id) {
    _controllers.putIfAbsent(
      id,
      () => StreamController<Landmark>.broadcast(),
    );
    return _controllers[id]!.stream;
  }

  void _notify(Landmark landmark) {
    final ctrl = _controllers[landmark.id];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(landmark);
    }
  }

  // ════════════════════════════════════════════════════════
  //  FRESHNESS CHECKS
  // ════════════════════════════════════════════════════════

  bool needsImageRefresh(String id) {
    final lm = get(id);
    if (lm == null) return true;
    final validCount = lm.mediaUrls.where(_isValidUrl).length;
    if (validCount < 3 || lm.imageUrl.trim().isEmpty) return true;
    if (lm.imagesRefreshedAt == null) return true;
    return _isExpired(lm.imagesRefreshedAt!, _imageTtl);
  }

  bool needsWikiRefresh(String id) {
    final lm = get(id);
    if (lm == null) return true;
    if (lm.shortDescription.trim().length < 60) return true;
    if (lm.wikiEnrichedAt == null) return true;
    return _isExpired(lm.wikiEnrichedAt!, _wikiTtl);
  }

  bool needsNearbyRefresh(String id) {
    final lm = get(id);
    if (lm == null) return true;
    if (lm.nearbyPlaces.isEmpty) return true;
    if (lm.nearbyUpdatedAt == null) return true;
    return _isExpired(lm.nearbyUpdatedAt!, _nearbyTtl);
  }

  // ════════════════════════════════════════════════════════
  //  INVALIDATE
  // ════════════════════════════════════════════════════════

  void invalidate(String id) => _store.remove(id);

  void clear() {
    _store.clear();
    for (final ctrl in _controllers.values) {
      if (!ctrl.isClosed) ctrl.close();
    }
    _controllers.clear();
  }

  // ════════════════════════════════════════════════════════
  //  MERGE LOGIC
  // ════════════════════════════════════════════════════════

  Landmark _mergeTwo(Landmark old, Landmark incoming) {
    final mergedMedia = _mergeUrls(
      old.imageUrl,
      old.mediaUrls,
      incoming.imageUrl,
      incoming.mediaUrls,
    );

    return old.copyWith(
      // Text: prefer longer/richer
      shortDescription:
          _betterText(incoming.shortDescription, old.shortDescription),
      description:
          _betterText(incoming.description, old.description),
      fullDescription:
          _betterText(incoming.fullDescription, old.fullDescription),
      history: _betterText(incoming.history, old.history),
      address: _betterText(incoming.address, old.address),
      openingHours: _betterText(incoming.openingHours, old.openingHours),

      // Images: merge and deduplicate
      imageUrl: mergedMedia.isNotEmpty ? mergedMedia.first : old.imageUrl,
      mediaUrls: mergedMedia,

      // Coordinates: take non-zero
      lat: incoming.lat != 0 ? incoming.lat : old.lat,
      lng: incoming.lng != 0 ? incoming.lng : old.lng,

      // Rating: take higher
      rating: incoming.rating > old.rating ? incoming.rating : old.rating,

      // Wikipedia: prefer non-null
      wikipediaUrl: (incoming.wikipediaUrl?.isNotEmpty == true)
          ? incoming.wikipediaUrl
          : old.wikipediaUrl,

      // Timestamps: take newer
      wikiEnrichedAt: _newerDate(incoming.wikiEnrichedAt, old.wikiEnrichedAt),
      imagesRefreshedAt:
          _newerDate(incoming.imagesRefreshedAt, old.imagesRefreshedAt),
      nearbyUpdatedAt:
          _newerDate(incoming.nearbyUpdatedAt, old.nearbyUpdatedAt),

      // Nearby: merge lists
      nearbyPlaces: _mergeNearby(old.nearbyPlaces, incoming.nearbyPlaces),
    );
  }

  List<String> _mergeUrls(
    String oldMain,
    List<String> oldList,
    String newMain,
    List<String> newList,
  ) {
    final seen = <String>{};
    final result = <String>[];

    String keyOf(String url) {
      final clean = url.trim();
      final lower = clean.toLowerCase();

      final unsplashMatch = RegExp(r'photo-[a-z0-9\-]+').firstMatch(lower);
      if (unsplashMatch != null) return 'unsplash:${unsplashMatch.group(0)}';

      final uri = Uri.tryParse(clean);
      if (uri == null) return lower;

      final pexelsMatch =
          RegExp(r'/(?:photos|photo)/(\d+)/?').firstMatch(uri.path.toLowerCase());
      if (pexelsMatch != null) return 'pexels:${pexelsMatch.group(1)}';

      return uri.replace(query: '', fragment: '').toString().toLowerCase();
    }

    void add(String url) {
      final clean = url.trim();
      if (clean.isNotEmpty && _isValidUrl(clean) && seen.add(keyOf(clean))) {
        result.add(clean);
      }
    }

    // Existing main image is stable — keep it first
    if (_isValidUrl(oldMain)) {
      add(oldMain);
    } else {
      add(newMain);
    }

    for (final u in oldList) add(u);
    for (final u in newList) add(u);
    if (_isValidUrl(newMain)) add(newMain);

    return result.take(7).toList();
  }

  List<Map<String, dynamic>> _mergeNearby(
    List<Map<String, dynamic>> old,
    List<Map<String, dynamic>> incoming,
  ) {
    final map = <String, Map<String, dynamic>>{};

    String keyOf(Map<String, dynamic> item) {
      final name = (item['name'] ?? '').toString().trim().toLowerCase();
      final lat = ((item['lat'] ?? 0) as num).toDouble().toStringAsFixed(4);
      final lng = ((item['lng'] ?? 0) as num).toDouble().toStringAsFixed(4);
      return '$name|$lat|$lng';
    }

    for (final item in old) {
      map[keyOf(item)] = Map<String, dynamic>.from(item);
    }
    for (final item in incoming) {
      final key = keyOf(item);
      map.putIfAbsent(key, () => Map<String, dynamic>.from(item));
    }

    return map.values.toList();
  }

  String _betterText(String a, String b) {
    final aClean = a.trim();
    final bClean = b.trim();
    if (aClean.length >= bClean.length && aClean.isNotEmpty) return aClean;
    return bClean.isNotEmpty ? bClean : aClean;
  }

  DateTime? _newerDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  bool _isExpired(DateTime date, Duration ttl) {
    return DateTime.now().difference(date) > ttl;
  }

  bool _isValidUrl(String url) {
    final u = url.trim();
    final lower = u.toLowerCase();

    const genericFallbackIds = [
      'photo-1539650116574-75c0c6d73f6e',
      'photo-1503177119275-0aa32b3a9368',
      'photo-1553913861-c0fddf2619ee',
      'photo-1572252009286-268acec5ca0a',
      'photo-1518548419970-58e3b4079ab2',
      'photo-1578922746465-3a80a228f223',
      'photo-1501785888041-af3ef285b470',
      'photo-1526772662000-3f88f10405ff',
      'photo-1500530855697-b586d89ba3ee',
      'photo-1505761671935-60b3a7427bad',
      'photo-1491553895911-0055eca6402d',
      'photo-1476514525535-07fb3b4ae5f1',
    ];

    if (genericFallbackIds.any(lower.contains)) return false;

    if (u.isEmpty || !(u.startsWith('http://') || u.startsWith('https://'))) {
      return false;
    }

    // Old external links from Wikimedia/Commons caused 429, PDFs, and decoder
    // crashes. Do not keep them in the in-memory merge result.
    if (lower.contains('upload.wikimedia.org') ||
        lower.contains('commons/thumb') ||
        lower.contains('source.unsplash.com') ||
        lower.contains('.pdf') ||
        lower.contains('.svg') ||
        lower.contains('.gif') ||
        lower.contains('.tif') ||
        lower.contains('.tiff') ||
        lower.contains('/wiki/file:') ||
        lower.contains('special:') ||
        lower.endsWith('.html')) {
      return false;
    }

    return true;
  }
}

class _Entry {
  final Landmark landmark;
  final DateTime cachedAt;
  const _Entry({required this.landmark, required this.cachedAt});
}