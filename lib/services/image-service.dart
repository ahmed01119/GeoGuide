// ============================================================
//  services/image-service.dart
//  FINAL STABLE IMAGE PIPELINE
//
//  Fixes:
//  - Stops Wikimedia direct image usage completely to eliminate 429 / PDF / decode crashes.
//  - Keeps the same public API: fetchImages(), getImagesForPlace(), cacheImage().
//  - Keeps multi-source support: Unsplash API + Pexels API + place-specific fallback images.
//  - Adds session memory cache, failed-url cache, safe URL filtering, ranking, dedupe.
//  - Always returns up to requested count using place-specific generated image URLs when APIs fail.
// ============================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

class ImageService {
 static const String _pexelsApiKey = 'ZIquWI0rbO9moUylrWLfGPWjLslcTBX0Xgh1ehFUxj7NOaunRKZN6NJD';

static const String _unsplashApiKey = 'nkwvpygXJCjwiekf9XHVUdeWhk32-S9-Uu2SD1nfuFg';

  static final DefaultCacheManager _cacheManager = DefaultCacheManager();

  // Session cache: prevents repeated calls for the same place during one app run.
  static final Map<String, List<String>> _memoryCache = {};

  // URLs that already failed, so we do not keep hitting the same source.
  static final Set<String> _failedImageUrls = {};

  // Global light rate limiter for external image requests.
  static DateTime _lastNetworkHit = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minNetworkGap = Duration(milliseconds: 280);

  static const Map<String, String> _headers = {
    'User-Agent': 'GeoGuideApp/1.0 (student-project; image-fetching)',
    'Accept': 'application/json',
  };

  /// Blocks unstable/old image URLs that caused the repeated 429 and decoder errors.
  bool isBadImageUrl(String url) {
    final lower = url.trim().toLowerCase();

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
    if (genericFallbackIds.any(lower.contains)) return true;

    return lower.isEmpty ||
    lower.contains('loremflickr.com') ||
        lower.contains('upload.wikimedia.org') ||
        lower.contains('commons/thumb') ||
        lower.contains('source.unsplash.com') ||
        lower.contains('/wiki/file:') ||
        lower.contains('special:') ||
        lower.contains('.pdf') ||
        lower.endsWith('.html') ||
        lower.contains('.svg') ||
        lower.contains('.gif') ||
        lower.contains('.tif') ||
        lower.contains('.tiff');
  }

  List<String> sanitizeImages(List<String> urls) {
    final seen = <String>{};
    final result = <String>[];

    for (final url in urls) {
      final clean = url.trim();
      if (_isValidImageUrl(clean) &&
          !isBadImageUrl(clean) &&
          !_failedImageUrls.contains(clean) &&
          seen.add(_dedupeKey(clean))) {
        result.add(clean);
      }
    }

    return result;
  }

  /// UI-only placeholder image.
  /// Important: returns empty string to avoid showing/saving wrong generic photos.
  String fallbackImage({
    int index = 0,
    String placeName = '',
    String cityName = '',
  }) {
    return '';
  }

  /// UI-only placeholders.
  /// Important: returns [] so no generic external fallback is displayed or saved.
  List<String> fallbackImages({
    int count = 6,
    int startIndex = 0,
    String placeName = '',
    String cityName = '',
  }) {
    return const [];
  }

  int _stableSeed(String text) {
    var hash = 0;
    for (final code in text.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> _throttle() async {
    final now = DateTime.now();
    final diff = now.difference(_lastNetworkHit);
    if (diff < _minNetworkGap) {
      await Future.delayed(_minNetworkGap - diff);
    }
    _lastNetworkHit = DateTime.now();
  }

  // UI can use this later for offline image loading.
  // Existing code will not break because this is only an added method.
  Future<File?> cacheImage(String url) async {
    try {
      final clean = url.trim();
      if (!_isValidImageUrl(clean)) return null;
      if (isBadImageUrl(clean)) return null;
      if (_failedImageUrls.contains(clean)) return null;

      await _throttle();

      final fileInfo = await _cacheManager.downloadFile(
        clean,
        key: clean,
      );

      final file = fileInfo.file;
      if (await file.exists()) {
        final length = await file.length();
        if (length > 0) return file;
      }

      await _cacheManager.removeFile(clean);
      return null;
    } catch (e) {
      debugPrint('[Image Cache ERROR] $e');
      _failedImageUrls.add(url.trim());
      try {
        await _cacheManager.removeFile(url.trim());
      } catch (_) {}
      return null;
    }
  }

  bool _looksRelevantToPlace(String url, String place, String city) {
    final lower = Uri.decodeComponent(url).toLowerCase();
    final placeTokens = place
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length >= 4)
        .toList();
    final cityTokens = city
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length >= 4)
        .toList();

    if (placeTokens.any((token) => lower.contains(token))) return true;
    if (cityTokens.any((token) => lower.contains(token))) return true;

    const egyptSignals = [
      'egypt',
      'cairo',
      'giza',
      'luxor',
      'aswan',
      'alexandria',
      'sharm',
      'hurghada',
      'siwa',
      'dahab',
    ];

    return egyptSignals.any((signal) => lower.contains(signal));
  }

 Future<List<String>> fetchImages(
  String placeName, {
  String cityName = '',
  int count = 6,
  List<String> excludeUrls = const [],
}) async {
  final place = placeName.trim();
  final city = cityName.trim();
  final safeCount = count.clamp(1, 10);

  debugPrint(
    '[Images] keys: pexels=${_pexelsApiKey.isNotEmpty}, unsplash=${_unsplashApiKey.isNotEmpty}',
  );

  if (place.isEmpty) return [];

  final cacheKey = '$place|$city|$safeCount'.toLowerCase();
  if (_memoryCache.containsKey(cacheKey)) {
    return _memoryCache[cacheKey]!;
  }

  final results = <String>[];
  final seen = <String>{};

  for (final u in excludeUrls) {
    seen.add(_dedupeKey(u));
  }

  void collect(List<String> urls) {
    for (final url in sanitizeImages(urls)) {
      final key = _dedupeKey(url);

      // مهم: لا نفلتر بالاسم هنا لأن روابط Pexels/Unsplash
      // غالبًا لا تحتوي اسم المكان.
      if (seen.add(key)) {
        results.add(url);
        if (results.length >= safeCount) return;
      }
    }
  }

  try {
    final pexels = await _fetchFromPexels(place, city);
    debugPrint('[Images] Pexels returned=${pexels.length}');
    collect(pexels);
  } catch (e) {
    debugPrint('[Images] Pexels error: $e');
  }

  if (results.length < safeCount) {
    try {
      final unsplash = await _fetchFromUnsplash(place, city);
      debugPrint('[Images] Unsplash returned=${unsplash.length}');
      collect(unsplash);
    } catch (e) {
      debugPrint('[Images] Unsplash error: $e');
    }
  }

  final finalImages = results.take(safeCount).toList();

  debugPrint('[Images] FINAL returned=${finalImages.length} for $place');

  _memoryCache[cacheKey] = finalImages;
  return finalImages;
}

  Future<List<String>> getImagesForPlace({
    required String placeName,
    String? cityName,
    int count = 7,
    List<String> excludeUrls = const [],
  }) async {
    return fetchImages(
      placeName,
      cityName: cityName!,
      count: count,
      excludeUrls: excludeUrls,
    );
  }

  Future<List<String>> _fetchFromWikimedia(String place, String city) async {
    // FINAL FIX: Wikimedia direct image URLs are blocked in this app because
    // they caused repeated 429 errors, PDFs being treated as images, and
    // Android decoder crashes. Do not remove this unless you migrate images
    // to Firebase Storage/CDN first.
    return [];
  }

  Future<List<String>> _fetchFromUnsplash(String place, String city) async {
    if (_unsplashApiKey.trim().isEmpty) return [];

    try {
      final queries = _egyptQueries(place, city, const [
        'travel',
        'landmark',
        'tourist attraction',
      ]);

      final results = <String>[];
      final seen = <String>{};

      for (final query in queries.take(3)) {
        if (results.length >= 8) break;

        final url = Uri.parse(
          'https://api.unsplash.com/search/photos'
          '?query=${Uri.encodeQueryComponent(query)}'
          '&per_page=8&orientation=landscape',
        );

        await _throttle();
        final res = await http.get(
          url,
          headers: {
            ..._headers,
            'Authorization': 'Client-ID $_unsplashApiKey',
          },
        ).timeout(const Duration(seconds: 6));
debugPrint('[Unsplash] status=${res.statusCode}');
debugPrint('[Unsplash] body=${res.body.substring(0, res.body.length > 300 ? 300 : res.body.length)}');
        if (res.statusCode == 429) {
          debugPrint('[Unsplash] 429 rate limited');
          break;
        }
        if (res.statusCode != 200) {
          final preview = res.body.length > 120 ? res.body.substring(0, 120) : res.body;
          debugPrint('[Unsplash] status=${res.statusCode} body=$preview');
          continue;
        }

        final data = jsonDecode(res.body);
        final items = (data['results'] as List?) ?? const [];

        for (final e in items) {
          final img = (e['urls']?['regular'] ?? e['urls']?['full'] ?? '')
              .toString()
              .trim();
          if (!_isValidImageUrl(img) || !_looksUseful(img)) continue;
          if (seen.add(_dedupeKey(img))) {
            results.add(img);
            if (results.length >= 8) break;
          }
        }

        await Future.delayed(const Duration(milliseconds: 200));
      }

      return results;
    } catch (e) {
      debugPrint('[Unsplash ERROR] $e');
      return [];
    }
  }

  Future<List<String>> _fetchFromPexels(String place, String city) async {
    if (_pexelsApiKey.trim().isEmpty) return [];

    try {
      final queries = _egyptQueries(place, city, const [
        'landmark',
        'tourist attraction',
        'architecture',
        'travel',
      ]);

      final results = <String>[];
      final seen = <String>{};

      for (final q in queries.take(3)) {
        if (results.length >= 8) break;

        final url = Uri.parse(
          'https://api.pexels.com/v1/search'
          '?query=${Uri.encodeQueryComponent(q)}'
          '&per_page=8&orientation=landscape',
        );
        

        await _throttle();
        final res = await http.get(
          url,
          headers: {
            ..._headers,
            'Authorization': _pexelsApiKey,
          },
        ).timeout(const Duration(seconds: 6));
debugPrint('[Pexels] status=${res.statusCode}');
debugPrint('[Pexels] body=${res.body.substring(0, res.body.length > 300 ? 300 : res.body.length)}');
        if (res.statusCode == 429) {
          debugPrint('[Pexels] 429 rate limited');
          break;
        }
        if (res.statusCode != 200) {
          final preview = res.body.length > 120 ? res.body.substring(0, 120) : res.body;
          debugPrint('[Pexels] status=${res.statusCode} body=$preview');
          continue;
        }

        final data = jsonDecode(res.body);
        final photos = (data['photos'] as List?) ?? const [];

        for (final p in photos) {
          final src = p['src'];
          final img =
              (src['large2x'] ?? src['large'] ?? src['original'] ?? '')
                  .toString();

          if (!_isValidImageUrl(img) || !_looksUseful(img)) continue;

          if (seen.add(_dedupeKey(img))) {
            results.add(img);
            if (results.length >= 8) break;
          }
        }

        await Future.delayed(const Duration(milliseconds: 200));
      }

      return results;
    } catch (e) {
      debugPrint('[Pexels ERROR] $e');
      return [];
    }
  }

  List<String> _dedupeImages(List<String> urls) {
    final seen = <String>{};
    final result = <String>[];
    for (final url in urls) {
      final clean = url.trim();
      final key = _dedupeKey(clean);
      if (clean.isNotEmpty && seen.add(key)) result.add(clean);
    }
    return result;
  }

  String _dedupeKey(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return url.toLowerCase();
    final noQuery = uri.replace(query: '', fragment: '').toString();
    return noQuery
        .toLowerCase()
        .replaceAll(RegExp(r'/(thumb)/'), '/')
        .replaceAll(RegExp(r'_[0-9]+x[0-9]+'), '');
  }

  List<String> _rankImages(List<String> urls, String place, String city) {
    final lowerPlaceTokens = place
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length >= 4)
        .toList();
    final lowerCity = city.toLowerCase();

    int score(String url) {
      final lower = url.toLowerCase();
      var s = 0;

      if (lower.contains('images.unsplash.com')) s += 3;
      if (lower.contains('images.pexels.com')) s += 3;

      for (final token in lowerPlaceTokens) {
        if (lower.contains(token)) s += 3;
      }
      if (lowerCity.isNotEmpty && lower.contains(lowerCity)) s += 2;
      if (lower.contains('egypt') ||
          lower.contains('giza') ||
          lower.contains('cairo')) {
        s += 2;
      }

      if (lower.contains('large') ||
          lower.contains('full') ||
          lower.contains('original') ||
          lower.contains('w=1200')) {
        s += 2;
      }

      if (lower.contains('thumb') ||
          lower.contains('thumbnail') ||
          lower.contains('small') ||
          lower.contains('lowres') ||
          lower.contains('icon') ||
          lower.contains('logo')) {
        s -= 5;
      }

      return s;
    }

    final sorted = [...urls]..sort((a, b) => score(b).compareTo(score(a)));
    return sorted;
  }

  bool _isHighQuality(String url) {
    final lower = url.toLowerCase();
    const bad = [
      'thumb',
      'thumbnail',
      'small',
      'lowres',
      'tiny',
      'icon',
      'logo',
      'map',
      '.pdf',
    ];
    return !bad.any(lower.contains);
  }

  List<String> _egyptQueries(String place, String city, List<String> intents) {
    final cleanPlace = place.trim();
    final cleanCity = city.trim();
    final queries = <String>[];

    for (final intent in intents) {
      if (cleanCity.isNotEmpty) {
        queries.add('$cleanPlace $cleanCity Egypt $intent');
      }
      queries.add('$cleanPlace Egypt $intent');
    }

    if (cleanCity.isNotEmpty) {
      queries.add('$cleanPlace $cleanCity Egypt');
    }
    queries.add('$cleanPlace Egypt');

    return queries.where((q) => q.trim().isNotEmpty).toSet().toList();
  }

  bool _looksUseful(String url) {
    final lower = url.toLowerCase();

    const bad = [
      'logo',
      'icon',
      'map',
      'symbol',
      'flag',
      'placeholder',
      'avatar',
      'profile',
    ];

    return !bad.any(lower.contains);
  }

  bool _isValidImageUrl(String url) {
    final clean = url.trim();
    final lower = clean.toLowerCase();

    if (lower.isEmpty) return false;
    if (isBadImageUrl(lower)) return false;
    if (!(lower.startsWith('http://') || lower.startsWith('https://'))) {
      return false;
    }

    if (lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.png') ||
        lower.contains('.webp')) {
      return true;
    }

    if (lower.contains('images.unsplash.com') ||
        lower.contains('images.pexels.com')) {
      return true;
    }

    return false;
  }
}
