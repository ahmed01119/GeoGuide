// ============================================================
// services/image-service.dart
// Version 12 - parallel exact-source search + confidence ranking
// Sources used in parallel:
//   1) Wikipedia page thumbnails
//   2) Pexels
//   3) Unsplash
// Policy:
//   - Search exact place name first, with city/category context.
//   - Rank all returned images by confidence.
//   - Only if exact search returns too few images, top-up with
//     category-safe fallback queries.
//   - Never return more than 6 images.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

class _CandidateImage {
  final String url;
  final int score;
  final String source;
  final bool isFallback;

  const _CandidateImage({
    required this.url,
    required this.score,
    required this.source,
    this.isFallback = false,
  });
}

class ImageService {
  static const int imagePipelineVersion = 20;

  static const String _pexelsApiKey = 'ZIquWI0rbO9moUylrWLfGPWjLslcTBX0Xgh1ehFUxj7NOaunRKZN6NJD';
  static const String _unsplashApiKey = 'nkwvpygXJCjwiekf9XHVUdeWhk32-S9-Uu2SD1nfuFg';

  static final DefaultCacheManager _cacheManager = DefaultCacheManager();
  static final Map<String, List<String>> _memoryCache = {};
  static final Set<String> _failedImageUrls = {};

  static DateTime _lastNetworkHit = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minNetworkGap = Duration(milliseconds: 220);

  static const Map<String, String> _headers = {
    'User-Agent': 'GeoGuideApp/1.0 (student-project; image-fetching)',
    'Accept': 'application/json',
  };

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
      final key = _dedupeKey(clean);
      if (_isValidImageUrl(clean) &&
          !isBadImageUrl(clean) &&
          !_failedImageUrls.contains(clean) &&
          seen.add(key)) {
        result.add(clean);
      }
    }

    return result;
  }

  Future<void> _throttle() async {
    final now = DateTime.now();
    final diff = now.difference(_lastNetworkHit);
    if (diff < _minNetworkGap) {
      await Future.delayed(_minNetworkGap - diff);
    }
    _lastNetworkHit = DateTime.now();
  }

  Future<File?> cacheImage(String url) async {
    try {
      final clean = url.trim();
      if (!_isValidImageUrl(clean)) return null;
      if (isBadImageUrl(clean)) return null;
      if (_failedImageUrls.contains(clean)) return null;

      await _throttle();
      final fileInfo = await _cacheManager.downloadFile(clean, key: clean);
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

  Future<List<String>> fetchImages(
    String placeName, {
    String cityName = '',
    String category = '',
    int count = 6,
    List<String> excludeUrls = const [],
  }) async {
    final originalPlace = placeName.trim();
    final place = _englishPlaceAlias(originalPlace);
    final city = cityName.trim();
    String normalizedCategory = _normalizeCategory(category);

    if (_looksTouristByName(place)) {
      normalizedCategory = 'tourist';
    }

    final safeCount = count.clamp(1, 6);
    debugPrint('[Images] start place=$place city=$city cat=$normalizedCategory');
    debugPrint('[Images] keys: pexels=${_pexelsApiKey.isNotEmpty}, unsplash=${_unsplashApiKey.isNotEmpty}');

    if (originalPlace.isEmpty) return [];

    if (_isGenericBusinessImageTarget(place, normalizedCategory)) {
      debugPrint('[Images] skipped generic business image target: $place');
      _memoryCache['$originalPlace|$place|$city|$normalizedCategory|$safeCount|pipeline_v$imagePipelineVersion'.toLowerCase()] = const [];
      return const [];
    }

    final cacheKey =
        '$originalPlace|$place|$city|$normalizedCategory|$safeCount|pipeline_v$imagePipelineVersion'
            .toLowerCase();
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey]!;
    }

    final excludedKeys = excludeUrls.map(_dedupeKey).toSet();
    final byKey = <String, _CandidateImage>{};

    void mergeCandidates(List<_CandidateImage> items) {
      for (final item in items) {
        final key = _dedupeKey(item.url);
        if (excludedKeys.contains(key)) continue;
        final existing = byKey[key];
        if (existing == null || item.score > existing.score) {
          byKey[key] = item;
        }
      }
    }

    final futures = <Future<List<_CandidateImage>>>[
      _fetchFromWikipediaCandidates(place, city, normalizedCategory),
      _fetchFromPexelsCandidates(place, city, normalizedCategory),
      _fetchFromUnsplashCandidates(place, city, normalizedCategory),
    ];

    final exactResults = await Future.wait(futures, eagerError: false);
    mergeCandidates(exactResults[0]);
    mergeCandidates(exactResults[1]);
    mergeCandidates(exactResults[2]);

    debugPrint('[Images] Wikipedia returned=${exactResults[0].length}');
    debugPrint('[Images] Pexels exact returned=${exactResults[1].length}');
    debugPrint('[Images] Unsplash exact returned=${exactResults[2].length}');

    // No generic fallback images: if the APIs cannot prove that the image
    // belongs to the exact place, we return fewer images rather than wrong ones.

    final ranked = byKey.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final finalImages = sanitizeImages(
      ranked.take(safeCount).map((e) => e.url).toList(),
    ).take(safeCount).toList();

    debugPrint('[Images] FINAL returned=${finalImages.length} for $place');
    _memoryCache[cacheKey] = finalImages;
    return finalImages;
  }

  Future<List<String>> getImagesForPlace({
    required String placeName,
    String? cityName,
    String category = '',
    int count = 6,
    List<String> excludeUrls = const [],
  }) async {
    return fetchImages(
      placeName,
      cityName: cityName ?? '',
      category: category,
      count: count,
      excludeUrls: excludeUrls,
    );
  }

  Future<List<_CandidateImage>> _fetchFromWikipediaCandidates(
    String place,
    String city,
    String category,
  ) async {
    final candidates = <_CandidateImage>[];
    final seen = <String>{};

    try {
      final queries = _queriesForPlace(place, city, category).take(2).toList();
      for (final query in queries) {
        final uri = Uri.parse(
          'https://en.wikipedia.org/w/api.php'
          '?action=query'
          '&generator=search'
          '&gsrsearch=${Uri.encodeQueryComponent(query)}'
          '&gsrnamespace=0'
          '&gsrlimit=6'
          '&prop=pageimages|extracts|info'
          '&piprop=thumbnail'
          '&pithumbsize=1600'
          '&pilimit=6'
          '&inprop=url'
          '&exintro=1'
          '&explaintext=1'
          '&format=json'
          '&origin=*',
        );

        await _throttle();
        final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
        if (res.statusCode != 200) continue;

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final pages = (data['query']?['pages'] as Map?) ?? const {};

        for (final raw in pages.values) {
          if (raw is! Map) continue;
          final page = Map<String, dynamic>.from(raw);
          final img = (page['thumbnail']?['source'] ?? '').toString().trim();
          if (!_isValidImageUrl(img) || !_looksUseful(img) || isBadImageUrl(img)) {
            continue;
          }

          final metaText = [
            page['title'],
            page['extract'],
            page['fullurl'],
          ].whereType<Object>().join(' ');

          final score = _imageConfidenceScore(
            meta: metaText,
            place: place,
            city: city,
            category: category,
            fromWikipedia: true,
            isFallback: false,
          );

          if (score < (_minimumScoreForCategory(category, place) - 8)) continue;

          final key = _dedupeKey(img);
          if (seen.add(key)) {
            candidates.add(_CandidateImage(
              url: img,
              score: score,
              source: 'wikipedia',
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('[Wikipedia image ERROR] $e');
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(6).toList();
  }

  Future<List<_CandidateImage>> _fetchFromCommonsCandidates(
    String place,
    String city,
    String category,
  ) async {
    final candidates = <_CandidateImage>[];
    final seen = <String>{};

    try {
      final queries = _queriesForPlace(place, city, category).take(5).toList();

      for (final query in queries) {
        if (candidates.length >= 10) break;

        final uri = Uri.parse(
          'https://commons.wikimedia.org/w/api.php'
          '?action=query'
          '&generator=search'
          '&gsrnamespace=6'
          '&gsrsearch=${Uri.encodeQueryComponent(query)}'
          '&gsrlimit=8'
          '&prop=imageinfo'
          '&iiprop=url|mime|extmetadata'
          '&format=json'
          '&origin=*',
        );

        await _throttle();
        final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 7));
        if (res.statusCode != 200) continue;

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final pages = (data['query']?['pages'] as Map?) ?? const {};

        for (final raw in pages.values) {
          if (raw is! Map) continue;
          final page = Map<String, dynamic>.from(raw);
          final imageInfoList = (page['imageinfo'] as List?) ?? const [];
          if (imageInfoList.isEmpty || imageInfoList.first is! Map) continue;

          final info = Map<String, dynamic>.from(imageInfoList.first as Map);
          final mime = (info['mime'] ?? '').toString().toLowerCase();
          if (!mime.startsWith('image/') || mime.contains('svg') || mime.contains('tiff')) {
            continue;
          }

          final img = (info['url'] ?? '').toString().trim();
          if (!_isValidImageUrl(img) || !_looksUseful(img) || isBadImageUrl(img)) {
            continue;
          }

          final ext = info['extmetadata'] is Map
              ? Map<String, dynamic>.from(info['extmetadata'] as Map)
              : const <String, dynamic>{};

          String extValue(String key) {
            final value = ext[key];
            if (value is Map) return (value['value'] ?? '').toString();
            return '';
          }

          final metaText = [
            page['title'],
            extValue('ObjectName'),
            extValue('ImageDescription'),
            extValue('Categories'),
            extValue('Credit'),
          ].whereType<Object>().join(' ');

          final score = _imageConfidenceScore(
            meta: metaText,
            place: place,
            city: city,
            category: category,
            fromWikipedia: true,
            isFallback: false,
          );

          // Commons filenames/descriptions are often cleaner than stock APIs,
          // but still require identity evidence. Keep the threshold close to Wikipedia.
          if (score < (_minimumScoreForCategory(category, place) - 10)) continue;

          final key = _dedupeKey(img);
          if (seen.add(key)) {
            candidates.add(_CandidateImage(
              url: img,
              score: score,
              source: 'wikimedia_commons',
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('[Wikimedia Commons image ERROR] $e');
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(6).toList();
  }

  Future<List<_CandidateImage>> _fetchFromUnsplashCandidates(
    String place,
    String city,
    String category, {
    bool useFallbackQueries = false,
  }) async {
    if (_unsplashApiKey.trim().isEmpty) return const [];
    final candidates = <_CandidateImage>[];
    final seen = <String>{};

    try {
      final queries = useFallbackQueries
          ? _fallbackQueriesForCategory(place, city, category)
          : _queriesForPlace(place, city, category);

      for (final query in queries.take(useFallbackQueries ? 2 : 4)) {
        if (candidates.length >= 14) break;

        final url = Uri.parse(
          'https://api.unsplash.com/search/photos'
          '?query=${Uri.encodeQueryComponent(query)}'
          '&per_page=10'
          '&orientation=landscape'
          '&page=${_apiPageFor(place, query, category)}',
        );

        await _throttle();
        final res = await http.get(
          url,
          headers: {
            ..._headers,
            'Authorization': 'Client-ID $_unsplashApiKey',
          },
        ).timeout(const Duration(seconds: 6));

        debugPrint('[Unsplash] status=${res.statusCode} query=$query');
        if (res.statusCode == 429) break;
        if (res.statusCode != 200) continue;

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final items = (data['results'] as List?) ?? const [];

        for (final e in items) {
          final map = e is Map ? Map<String, dynamic>.from(e) : const <String, dynamic>{};
          final img = (map['urls']?['regular'] ?? map['urls']?['full'] ?? '')
              .toString()
              .trim();

          if (!_isValidImageUrl(img) || !_looksUseful(img) || isBadImageUrl(img)) {
            continue;
          }

          final metaText = [
            map['slug'],
            map['description'],
            map['alt_description'],
            map['user']?['name'],
          ].whereType<Object>().join(' ');

          final score = _imageConfidenceScore(
            meta: metaText,
            place: place,
            city: city,
            category: category,
            fromWikipedia: false,
            isFallback: useFallbackQueries,
          );

          final threshold = _minimumScoreForCategory(category, place);
          if (score < threshold) continue;

          final key = _dedupeKey(img);
          if (seen.add(key)) {
            candidates.add(_CandidateImage(
              url: img,
              score: score,
              source: 'unsplash',
              isFallback: useFallbackQueries,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('[Unsplash ERROR] $e');
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }

  Future<List<_CandidateImage>> _fetchFromPexelsCandidates(
    String place,
    String city,
    String category, {
    bool useFallbackQueries = false,
  }) async {
    if (_pexelsApiKey.trim().isEmpty) return const [];
    final candidates = <_CandidateImage>[];
    final seen = <String>{};

    try {
      final queries = useFallbackQueries
          ? _fallbackQueriesForCategory(place, city, category)
          : _queriesForPlace(place, city, category);

      for (final q in queries.take(useFallbackQueries ? 2 : 4)) {
        if (candidates.length >= 14) break;

        final url = Uri.parse(
          'https://api.pexels.com/v1/search'
          '?query=${Uri.encodeQueryComponent(q)}'
          '&per_page=10'
          '&orientation=landscape'
          '&page=${_apiPageFor(place, q, category)}',
        );

        await _throttle();
        final res = await http.get(
          url,
          headers: {
            ..._headers,
            'Authorization': _pexelsApiKey,
          },
        ).timeout(const Duration(seconds: 6));

        debugPrint('[Pexels] status=${res.statusCode} query=$q');
        if (res.statusCode == 429) break;
        if (res.statusCode != 200) continue;

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final photos = (data['photos'] as List?) ?? const [];

        for (final p in photos) {
          final map = p is Map ? Map<String, dynamic>.from(p) : const <String, dynamic>{};
          final src = map['src'];
          final img = (src is Map
                  ? (src['large2x'] ?? src['large'] ?? src['original'] ?? '')
                  : '')
              .toString()
              .trim();

          if (!_isValidImageUrl(img) || !_looksUseful(img) || isBadImageUrl(img)) {
            continue;
          }

          final metaText = [
            map['url'],
            map['alt'],
            map['photographer'],
          ].whereType<Object>().join(' ');

          final score = _imageConfidenceScore(
            meta: metaText,
            place: place,
            city: city,
            category: category,
            fromWikipedia: false,
            isFallback: useFallbackQueries,
          );

          final threshold = _minimumScoreForCategory(category, place);
          if (score < threshold) continue;

          final key = _dedupeKey(img);
          if (seen.add(key)) {
            candidates.add(_CandidateImage(
              url: img,
              score: score,
              source: 'pexels',
              isFallback: useFallbackQueries,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('[Pexels ERROR] $e');
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }

  // =================== Ranking helpers ===================


  bool _isGenericBusinessImageTarget(String place, String category) {
    final cat = _normalizeCategory(category);
    if (cat != 'cafe' && cat != 'restaurant' && cat != 'hotel') return false;

    final normalized = _normalizeText(place);
    if (normalized.isEmpty) return true;

    const genericNames = {
      'caf', 'cafe', 'cafeteria', 'coffee', 'coffee shop',
      'restaurant', 'hotel', 'rest house', 'unknown', 'unnamed',
    };
    if (genericNames.contains(normalized)) return true;

    if (normalized.length < 4) return true;

    final roadLike = RegExp(
      r'\b(street|road|avenue|square|district|quarter|neighbourhood|neighborhood|area|route|bridge)\b',
    ).hasMatch(normalized) ||
        RegExp(r'(شارع|طريق|ميدان|منطقة|حي|كوبري|محور)').hasMatch(place);
    if (roadLike) return true;

    return false;
  }

  bool _looksTouristByName(String placeLower) {
    final p = placeLower.toLowerCase();
    return [
      'pyramid',
      'sphinx',
      'temple',
      'museum',
      'citadel',
      'mosque',
      'church',
      'palace',
      'castle',
      'tomb',
      'ruins',
      'monument',
      'landmark',
      'library',
      'tower',
    ].any(p.contains);
  }

  bool _hasLatinLetters(String text) => RegExp(r'[a-zA-Z]').hasMatch(text);
  bool _hasArabicLetters(String value) => RegExp(r'[\u0600-\u06FF]').hasMatch(value);

  String _latinOnlyName(String value) {
    final tokens = value
        .split(RegExp(r'\s+'))
        .where((token) => RegExp(r'[a-zA-Z]').hasMatch(token))
        .map((token) => token.replaceAll(RegExp(r"[^a-zA-Z0-9&\-']+"), ''))
        .where((token) => token.trim().isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return tokens;
  }

  String _englishPlaceAlias(String place) {
    final p = place.trim().toLowerCase();
    const aliases = {
      'قهوة ريش': 'Cafe Riche',
      'كافيه ريش': 'Cafe Riche',
      'مقهى ريش': 'Cafe Riche',
      'cafe riche': 'Cafe Riche',
      'citadel of cairo': 'Cairo Citadel',
      'cairo citadel': 'Cairo Citadel',
      'saladin citadel': 'Cairo Citadel',
      'قلعة صلاح الدين': 'Cairo Citadel',
      'قلعه صلاح الدين': 'Cairo Citadel',
      'ريش': 'Cafe Riche',
      'الفيشاوي': 'El Fishawy Cafe',
      'قهوة الفيشاوي': 'El Fishawy Cafe',
      'كافيه الفيشاوي': 'El Fishawy Cafe',
      'fishawy': 'El Fishawy Cafe',
      'el fishawy': 'El Fishawy Cafe',
      'نجيب محفوظ كافيه': 'Naguib Mahfouz Cafe',
      'كافيه نجيب محفوظ': 'Naguib Mahfouz Cafe',
      'naguib mahfouz cafe': 'Naguib Mahfouz Cafe',
      'جروبي': 'Groppi Cafe',
      'groppi': 'Groppi Cafe',
      'groppi cafe': 'Groppi Cafe',
      'groppi cairo': 'Groppi Cafe',
      'مطعم صبحي كابر': 'Sobhy Kaber Restaurant',
      'صبحي كابر': 'Sobhy Kaber Restaurant',
      'sobhy kaber': 'Sobhy Kaber Restaurant',
      'كشري التحرير': 'Koshary El Tahrir',
      'koshary el tahrir': 'Koshary El Tahrir',
      'مكتبة الإسكندرية': 'Bibliotheca Alexandrina',
      'مكتبه الاسكندريه': 'Bibliotheca Alexandrina',
      'قصر عابدين': 'Abdeen Palace',
      'قصر المنتزه': 'Montaza Palace',
      'أبو الهول': 'Great Sphinx of Giza',
      'ابو الهول': 'Great Sphinx of Giza',
      'أهرامات الجيزة': 'Pyramids of Giza',
      'اهرامات الجيزه': 'Pyramids of Giza',
      'وادي الملوك': 'Valley of the Kings',
      'معبد فيلة': 'Philae Temple',
      'معبد فيله': 'Philae Temple',
      'معبد الأقصر': 'Luxor Temple',
      'معبد الاقصر': 'Luxor Temple',
      'معبد الكرنك': 'Karnak Temple',
      'قلعة قايتباي': 'Citadel of Qaitbay',
    };
    final alias = aliases[p];
    if (alias != null) return alias;

    final latinOnly = _latinOnlyName(place);
    if (latinOnly.isNotEmpty && _hasArabicLetters(place)) {
      return latinOnly;
    }

    return place.trim();
  }

  String _normalizeText(String value) {
    return value
        .toLowerCase()
        .replaceAll('pyrmaid', 'pyramid')
        .replaceAll('piramide', 'pyramid')
        .replaceAll('pyramids', 'pyramid')
        .replaceAll('café', 'cafe')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _strongPlaceTokens(String place) {
    final p = _normalizeText(place);

    // General rule only: extract meaningful words from ANY place name.
    // Do not hardcode places. A token becomes strong if it is not just a country,
    // city, connector, or broad category word. If nothing remains, keep the
    // strongest subtype word so places like "Cairo Tower" still require "tower".
    const weakTokens = {
      'egypt', 'giza', 'cairo', 'alexandria', 'luxor', 'aswan', 'hurghada',
      'sharm', 'dahab', 'siwa', 'of', 'the', 'and', 'in', 'at', 'near',
      'great', 'new', 'old', 'egyptian', 'tourist', 'attraction', 'landmark',
      'restaurant', 'restaurants', 'cafe', 'coffee', 'hotel', 'resort',
      'district', 'street', 'road', 'square', 'city', 'governorate',
    };

    final tokens = p
        .split(' ')
        .where((t) => t.length >= 4 && !weakTokens.contains(t))
        .toList();

    if (tokens.isNotEmpty) return tokens.toSet().toList();

    const subtypeTokens = {
      'tower', 'citadel', 'palace', 'temple', 'museum', 'sphinx', 'pyramid',
      'mosque', 'church', 'library', 'fort', 'castle', 'park', 'garden',
      'beach', 'mall', 'zoo', 'aquarium',
    };

    final fallback = p
        .split(' ')
        .where((t) => subtypeTokens.contains(t))
        .toList();

    return fallback.toSet().toList();
  }

  List<String> _identityTokens(String place) {
    final subtypeWords = <String>{
      'tower', 'citadel', 'palace', 'temple', 'museum', 'sphinx', 'pyramid',
      'mosque', 'church', 'library', 'fort', 'castle', 'park', 'garden',
      'beach', 'mall', 'restaurant', 'cafe', 'coffee', 'hotel', 'resort',
    };

    return _strongPlaceTokens(place)
        .where((t) => !subtypeWords.contains(t))
        .toList();
  }

  bool _isGenericNamedPlace(String place) {
    final normalized = _normalizeText(place);
    if (normalized.isEmpty) return false;

    final words = normalized.split(' ').where((w) => w.length >= 3).toList();
    if (words.length < 2) return false;

    // Generic named places are names where the meaningful part is mainly
    // a city + a broad subtype, e.g. Cairo Tower / Luxor Temple. For these
    // names, matching only "tower" or "temple" is not enough; the real
    // metadata must contain the full phrase or very strong identity evidence.
    return _identityTokens(place).isEmpty && _strongPlaceTokens(place).isNotEmpty;
  }

  String _expectedSubtype(String place, String category) {
    final p = _normalizeText(place);
    final cat = _normalizeCategory(category);
    if (cat == 'cafe') return 'cafe';
    if (cat == 'restaurant') return 'restaurant';
    if (cat == 'hotel') return 'hotel';
    if (cat == 'outing') return 'outing';
    if (p.contains('temple')) return 'temple';
    if (p.contains('palace')) return 'palace';
    if (p.contains('citadel')) return 'citadel';
    if (p.contains('museum')) return 'museum';
    if (p.contains('library') || p.contains('bibliotheca')) return 'library';
    if (p.contains('tower')) return 'tower';
    if (p.contains('sphinx')) return 'sphinx';
    if (p.contains('pyramid')) return 'pyramid';
    if (p.contains('mosque')) return 'mosque';
    if (p.contains('church')) return 'church';
    return cat;
  }

  List<String> _subtypeKeywords(String subtype) {
    switch (subtype) {
      case 'temple': return ['temple'];
      case 'palace': return ['palace'];
      case 'citadel': return ['citadel', 'fortress', 'saladin'];
      case 'museum': return ['museum'];
      case 'library': return ['library', 'bibliotheca'];
      case 'tower': return ['tower'];
      case 'sphinx': return ['sphinx'];
      case 'pyramid': return ['pyramid'];
      case 'mosque': return ['mosque'];
      case 'church': return ['church', 'cathedral'];
      case 'cafe': return ['cafe', 'coffee', 'coffee shop', 'coffeehouse', 'tea'];
      case 'restaurant': return ['restaurant', 'dining', 'food', 'meal'];
      case 'hotel': return ['hotel', 'resort', 'lobby', 'suite', 'room'];
      case 'outing': return ['park', 'garden', 'beach', 'mall', 'entertainment'];
      default: return const [];
    }
  }

  List<String> _conflictingSubtypeWords(String subtype) {
    switch (subtype) {
      case 'temple': return ['sphinx', 'pyramid', 'citadel', 'palace'];
      case 'palace': return ['temple', 'sphinx', 'pyramid', 'citadel'];
      case 'citadel': return ['qaitbay', 'temple', 'sphinx', 'pyramid', 'palace'];
      case 'museum': return ['temple', 'sphinx', 'pyramid', 'citadel'];
      case 'library': return ['temple', 'sphinx', 'pyramid', 'citadel', 'palace'];
      case 'tower': return ['temple', 'sphinx', 'pyramid'];
      case 'cafe': return ['pyramid', 'sphinx', 'temple', 'museum', 'citadel'];
      case 'restaurant': return ['pyramid', 'sphinx', 'temple', 'museum', 'citadel'];
      case 'hotel': return ['pyramid', 'sphinx', 'temple', 'museum', 'citadel'];
      default: return const [];
    }
  }

  int _minimumScoreForCategory(String category, String place) {
    final cat = _normalizeCategory(category);
    final hasIdentity = _identityTokens(place).isNotEmpty;
    final genericName = _isGenericNamedPlace(place);

    if (genericName) return 72;
    if (cat == 'tourist') return hasIdentity ? 64 : 58;
    if (cat == 'hotel') return hasIdentity ? 62 : 56;
    if (cat == 'restaurant') return hasIdentity ? 62 : 56;
    if (cat == 'cafe') return hasIdentity ? 62 : 56;
    if (cat == 'outing') return hasIdentity ? 58 : 52;
    return 60;
  }

  bool _hasCategoryVisualSignal(String meta, String category) {
    final cat = _normalizeCategory(category);
    final lower = meta.toLowerCase();
    if (cat == 'cafe') {
      return ['cafe', 'coffee', 'espresso', 'latte', 'bakery', 'tea', 'coffee shop', 'coffeehouse', 'cup', 'table', 'shisha', 'hookah']
          .any(lower.contains);
    }
    if (cat == 'restaurant') {
      return ['restaurant', 'dining', 'food', 'meal', 'cuisine', 'dish', 'kitchen', 'menu', 'table']
          .any(lower.contains);
    }
    if (cat == 'hotel') {
      return ['hotel', 'resort', 'room', 'lobby', 'suite', 'pool', 'reception']
          .any(lower.contains);
    }
    if (cat == 'outing') {
      return ['park', 'garden', 'beach', 'seaside', 'entertainment', 'mall', 'cinema']
          .any(lower.contains);
    }
    return true;
  }

  bool _looksAllowedForCategory(String metaText, String category) {
    final cat = _normalizeCategory(category);
    final lower = metaText.toLowerCase();

    if (cat == 'tourist') {
      return ['museum', 'palace', 'temple', 'citadel', 'fort', 'castle', 'pyramid', 'sphinx', 'mosque', 'church', 'ruins', 'monument', 'landmark', 'heritage', 'library', 'tower', 'historic', 'archaeological']
              .any(lower.contains) ||
          lower.contains('egypt');
    }

    if (cat == 'restaurant') {
      return ['restaurant', 'dining', 'food', 'meal', 'cuisine', 'dish', 'menu', 'table', 'served']
          .any(lower.contains);
    }
    if (cat == 'cafe') {
      return ['cafe', 'coffee', 'espresso', 'bakery', 'tea', 'coffee shop', 'coffeehouse', 'cup', 'table', 'shisha', 'hookah']
          .any(lower.contains);
    }
    if (cat == 'hotel') {
      return ['hotel', 'resort', 'room', 'lobby', 'suite', 'pool', 'reception']
          .any(lower.contains);
    }
    return true;
  }

  int _imageConfidenceScore({
    required String meta,
    required String place,
    required String city,
    required String category,
    required bool fromWikipedia,
    required bool isFallback,
  }) {
    final text = _normalizeText(meta);
    final p = _normalizeText(place);
    final c = _normalizeText(city);
    final cat = _normalizeCategory(category);
    final strongTokens = _strongPlaceTokens(place);
    final expectedSubtype = _expectedSubtype(place, category);
    final genericNamedPlace = _isGenericNamedPlace(place);

    int score = 0;

    if (fromWikipedia) score += 110;
    if (isFallback) score -= 22;
    final hasFullPhrase = p.isNotEmpty && text.contains(p);
    if (hasFullPhrase) score += 95;

    if (genericNamedPlace && !hasFullPhrase) {
      // A generic name like "Cairo Tower" or "Luxor Temple" must match
      // the full phrase. City + subtype alone is exactly what caused wrong
      // mosque/citadel/temple photos to pass before.
      score -= fromWikipedia ? 45 : 95;
    }

    final matchedStrong = strongTokens.where((t) => text.contains(t)).length;
    score += matchedStrong * 24;

    final identityTokens = _identityTokens(place);
    final matchedIdentity = identityTokens.where((t) => text.contains(t)).length;

    // General rule: for a named place, city/category/subtype alone is not enough.
    // If a name has an identity token, at least one identity token should appear
    // in the real metadata. This catches wrong city-level photos for all places,
    // not just a hardcoded list.
    if (identityTokens.isNotEmpty && matchedIdentity == 0 && !hasFullPhrase) {
      score -= isFallback ? 40 : 72;
    } else if (matchedIdentity > 0) {
      score += matchedIdentity * 28;
    }

    if (strongTokens.isNotEmpty && matchedStrong == 0 && !hasFullPhrase) {
      score -= isFallback ? 32 : 58;
    }

    if (c.isNotEmpty && text.contains(c)) score += 12;
    if (text.contains('egypt')) score += 8;

    final subtypeWords = _subtypeKeywords(expectedSubtype);
    final conflicting = _conflictingSubtypeWords(expectedSubtype);
    if (subtypeWords.isNotEmpty && subtypeWords.any(text.contains)) {
      score += 20;
    } else if (_looksTouristByName(place) || cat != 'tourist') {
      score -= 18;
    }
    if (conflicting.any(text.contains)) score -= 35;

    // City/category alone must not be enough for a specific named place.
    // The APIs often return photos from the same city but not the same place.
    if (!isFallback && strongTokens.isNotEmpty && matchedStrong == 0 && !hasFullPhrase) {
      score -= 35;
    }

    if (_hasCategoryVisualSignal(text, cat)) score += 15;
    if (_looksAllowedForCategory(text, cat)) score += 12;

    const badSignals = [
      'traffic', 'car ', 'truck', 'van', 'soccer', 'football', 'stadium',
      'screen', 'skyline', 'sign', 'street sign', 'map', 'logo', 'icon',
    ];
    for (final bad in badSignals) {
      if (text.contains(bad)) score -= 22;
    }

    return score;
  }

  int _apiPageFor(String place, String query, String category) {
    final seed = _stableSeed('$place|$query|$category');
    return 1 + (seed % 3);
  }

  int _stableSeed(String text) {
    var hash = 0;
    for (final code in text.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash;
  }

  String _normalizeCategory(String category) {
    final c = category.trim().toLowerCase();
    if (c.contains('restaurant') || c.contains('restaurants') || c.contains('resturant') || c.contains('resturants') || c.contains('restraunt') || c.contains('restraunts') || c.contains('dining') || c.contains('food')) {
      return 'restaurant';
    }
    if (c.contains('cafe') || c.contains('coffee')) return 'cafe';
    if (c.contains('hotel') || c.contains('resort') || c.contains('lodging')) return 'hotel';
    if (c.contains('outing') || c.contains('park') || c.contains('entertainment')) return 'outing';
    return 'tourist';
  }

  List<String> _queriesForPlace(String place, String city, String category) {
    final cleanPlace = _englishPlaceAlias(place).trim();
    final cleanCity = city.trim();
    final cat = _normalizeCategory(category);
    final catWord = cat == 'tourist' ? 'landmark' : cat;
    final queries = <String>[];

    void add(String q) {
      final clean = q.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (clean.isNotEmpty && !queries.contains(clean)) queries.add(clean);
    }

    final aliases = _exactQueryAliases(cleanPlace);
    for (final alias in aliases) {
      add('$alias $cleanCity Egypt');
      add('$alias $catWord $cleanCity Egypt');
      add('$alias Egypt');
      add('$alias $catWord Egypt');
    }

    if (queries.isEmpty) {
      final subject = _englishSubjectForImageSearch(cleanPlace, cat);
      add('$subject $cleanCity Egypt');
      add('$subject Egypt');
    }

    return queries.take(8).toList();
  }

  List<String> _exactQueryAliases(String place) {
    final clean = place.trim().replaceAll(RegExp(r'\s+'), ' ');
    final result = <String>[];

    void add(String value) {
      final v = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (v.isNotEmpty && !result.contains(v)) result.add(v);
    }

    add(clean);

    final normalizedClean = _normalizeText(clean);
    if (normalizedClean.endsWith(' cafe')) {
      final base = clean.replaceFirst(RegExp(r'\s+[Cc]afe$'), '').trim();
      add(base);
      add('Cafe $base');
      add('$base Coffee');
    }
    if (normalizedClean.endsWith(' restaurant')) {
      final base = clean.replaceFirst(RegExp(r'\s+[Rr]estaurant$'), '').trim();
      add(base);
      add('$base Egypt');
    }
    if (normalizedClean.endsWith(' hotel')) {
      final base = clean.replaceFirst(RegExp(r'\s+[Hh]otel$'), '').trim();
      add(base);
    }

    final normalized = _normalizeText(clean);
    final words = normalized.split(' ').where((w) => w.isNotEmpty).toList();

    final ofMatch = RegExp(r'^([a-z0-9 ]+) of ([a-z0-9 ]+)').firstMatch(normalized);
    if (ofMatch != null) {
      final left = ofMatch.group(1)!.trim();
      final right = ofMatch.group(2)!.trim();
      add('$right $left');
      add('$left of $right');
    }

    const subtypes = {
      'tower', 'citadel', 'palace', 'temple', 'museum', 'library', 'mosque',
      'church', 'pyramid', 'sphinx', 'fort', 'castle', 'cafe', 'restaurant',
      'hotel', 'resort', 'park', 'garden', 'beach', 'mall'
    };
    const cityWords = {
      'cairo', 'giza', 'alexandria', 'luxor', 'aswan', 'hurghada', 'sharm',
      'dahab', 'siwa'
    };
    for (final subtype in subtypes) {
      if (!words.contains(subtype)) continue;
      for (final city in cityWords) {
        if (words.contains(city)) {
          add('$city $subtype');
          add('$subtype of $city');
        }
      }
    }

    if (words.length >= 3) {
      for (var i = 0; i < words.length - 1; i++) {
        final a = words[i];
        final b = words[i + 1];
        if (subtypes.contains(a) || subtypes.contains(b)) {
          add('$a $b');
        }
      }
    }

    return result.take(5).toList();
  }

  List<String> _fallbackQueriesForCategory(String place, String city, String category) {
    final cleanCity = city.trim();
    final cat = _normalizeCategory(category);
    final queries = <String>[];

    void add(String q) {
      final clean = q.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (clean.isNotEmpty && !queries.contains(clean)) queries.add(clean);
    }

    switch (cat) {
      case 'cafe':
        add('traditional cafe in $cleanCity Egypt');
        add('coffee shop in $cleanCity Egypt');
        break;
      case 'restaurant':
        add('restaurant dining in $cleanCity Egypt');
        add('egyptian food restaurant in $cleanCity');
        break;
      case 'hotel':
        add('hotel resort in $cleanCity Egypt');
        add('hotel lobby room in $cleanCity Egypt');
        break;
      case 'outing':
        add('park beach entertainment in $cleanCity Egypt');
        add('outing place in $cleanCity Egypt');
        break;
      case 'tourist':
      default:
        final subtype = _expectedSubtype(place, category);
        final subtypeWords = _subtypeKeywords(subtype).join(' ');
        add('$subtypeWords in $cleanCity Egypt');
        add('tourist attraction $cleanCity Egypt');
        break;
    }
    return queries.take(2).toList();
  }

  String _englishSubjectForImageSearch(String place, String category) {
    final normalized = _normalizeCategory(category);
    final trimmed = place.trim();
    final lower = trimmed.toLowerCase();
    if (_hasLatinLetters(trimmed)) return trimmed;
    if (_hasArabicLetters(trimmed)) {
      switch (normalized) {
        case 'cafe': return 'cafe coffee shop';
        case 'restaurant': return 'restaurant dining';
        case 'hotel': return 'hotel resort';
        case 'outing': return 'outing place';
        case 'tourist':
        default: return 'tourist attraction';
      }
    }
    if (lower.isEmpty) return 'tourist attraction';
    return trimmed;
  }

  bool _looksUseful(String url) {
    final lower = url.toLowerCase();
    const bad = ['logo', 'icon', 'map', 'symbol', 'flag', 'placeholder', 'avatar', 'profile'];
    return !bad.any(lower.contains);
  }

  String _dedupeKey(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return '${uri.host}${uri.path}';
  }

  bool _isValidImageUrl(String url) {
    final clean = url.trim();
    final lower = clean.toLowerCase();
    if (lower.isEmpty) return false;
    if (isBadImageUrl(lower)) return false;
    if (!(lower.startsWith('http://') || lower.startsWith('https://'))) {
      return false;
    }
    if (lower.contains('.jpg') || lower.contains('.jpeg') || lower.contains('.png') || lower.contains('.webp')) {
      return true;
    }
    if (lower.contains('images.unsplash.com') || lower.contains('images.pexels.com') || lower.contains('upload.wikimedia.org')) {
      return true;
    }
    return false;
  }
}
