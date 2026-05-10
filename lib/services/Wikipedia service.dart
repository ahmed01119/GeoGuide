// ============================================================
//  services/wikipedia_service.dart
// ============================================================

import 'package:dio/dio.dart';

class WikipediaResult {
  final String title;
  final String summary;
  final String fullText;
  final String pageUrl;

  const WikipediaResult({
    required this.title,
    required this.summary,
    required this.fullText,
    required this.pageUrl,
  });
}

class WikipediaService {
  static const String _apiUrl = 'https://en.wikipedia.org/w/api.php';
  final Dio _dio;

  static final Map<String, String?> _titleCache = {};
  static final Map<String, WikipediaResult?> _resultCache = {};
  static DateTime _lastWikiHit = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _wikiGap = Duration(milliseconds: 350);

  WikipediaService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 8),
      headers: const {
        'User-Agent': 'GeoGuideApp/1.0 (student-project; wikipedia-fetching)',
        'Accept': 'application/json',
      },
    );
  }

  Future<void> _throttle() async {
    final now = DateTime.now();
    final diff = now.difference(_lastWikiHit);
    if (diff < _wikiGap) {
      await Future.delayed(_wikiGap - diff);
    }
    _lastWikiHit = DateTime.now();
  }

  static const List<String> _egyptKeywords = [
    'egypt',
    'cairo',
    'giza',
    'luxor',
    'aswan',
    'alexandria',
    'hurghada',
    'sharm',
    'siwa',
    'tourist',
    'temple',
    'museum',
    'mosque',
    'church',
    'monastery',
    'palace',
    'citadel',
    'pyramid',
    'tomb',
    'island',
    'beach',
    'park',
    'histor',
    'archae',
    'landmark',
    'مصر',
    'القاهرة',
    'الجيزة',
    'الأقصر',
    'أسوان',
    'الإسكندرية',
    'الغردقة',
    'شرم',
    'سيوة',
  ];

  static const List<String> _personPatterns = [
    'born',
    'actor',
    'actress',
    'footballer',
    'politician',
    'singer',
    'author',
    'director',
    'comedian',
    'journalist',
    'egyptian actor',
    'egyptian footballer',
    'was born',
    'ولد',
    'ممثل',
    'لاعب',
    'مغني',
    'سياسي',
    'كاتب',
    'مخرج',
  ];

  static const List<String> _abstractPatterns = [
    'ancient egypt',
    'history of egypt',
    'egyptian history',
    'economy of egypt',
    'culture of egypt',
    'egypt in the',
    'governorate',
    'is a city in',
    'is a capital',
    'is a country',
    'is a period',
    'is a civilization',
    'is a concept',
    'refers to',
    'list of',
    'category:',
    'disambiguation',
  ];


  String _canonicalEnglishQuery(String value) {
    final raw = value.trim();
    final normalized = _normalize(raw);
    if (normalized.isEmpty) return raw;

    const aliases = {
      'قهوة ريش': 'Cafe Riche',
      'كافيه ريش': 'Cafe Riche',
      'مقهى ريش': 'Cafe Riche',
      'ريش': 'Cafe Riche',
      'cafe riche': 'Cafe Riche',
      'قهوة الفيشاوي': 'El Fishawy Cafe',
      'كافيه الفيشاوي': 'El Fishawy Cafe',
      'الفيشاوي': 'El Fishawy Cafe',
      'el fishawy': 'El Fishawy Cafe',
      'fishawy': 'El Fishawy Cafe',
      'نجيب محفوظ كافيه': 'Naguib Mahfouz Cafe',
      'كافيه نجيب محفوظ': 'Naguib Mahfouz Cafe',
      'جروبي': 'Groppi Cafe',
      'groppi': 'Groppi Cafe',
      'خان الخليلي': 'Khan el-Khalili',
      'خان الخليل': 'Khan el-Khalili',
      'khan el khalili': 'Khan el-Khalili',
      'khan el-khalili': 'Khan el-Khalili',
      'المتحف المصري الكبير': 'Grand Egyptian Museum',
      'المتحف المصري': 'Egyptian Museum',
      'برج القاهرة': 'Cairo Tower',
      'قصر عابدين': 'Abdeen Palace',
      'قصر المنتزه': 'Montaza Palace',
      'مكتبة الإسكندرية': 'Bibliotheca Alexandrina',
      'وادي الملوك': 'Valley of the Kings',
      'معبد الأقصر': 'Luxor Temple',
      'معبد الكرنك': 'Karnak Temple',
      'معبد حتشبسوت': 'Temple of Hatshepsut',
      'معبد فيلة': 'Philae Temple',
      'أبو سمبل': 'Abu Simbel Temples',
      'أبو الهول': 'Great Sphinx of Giza',
      'ابو الهول': 'Great Sphinx of Giza',
      'أهرامات الجيزة': 'Pyramids of Giza',
      'اهرامات الجيزه': 'Pyramids of Giza',
      'واحة سيوة': 'Siwa Oasis',
    };

    for (final entry in aliases.entries) {
      final key = _normalize(entry.key);
      if (normalized == key || normalized.contains(key)) return entry.value;
    }

    return raw;
  }

  Future<WikipediaResult?> search(
    String placeName, {
    String? cityName,
  }) async {
    final canonicalPlaceName = _canonicalEnglishQuery(placeName);
    final resultKey = '${canonicalPlaceName.trim().toLowerCase()}|${(cityName ?? '').trim().toLowerCase()}';
    if (_resultCache.containsKey(resultKey)) return _resultCache[resultKey];

    final pageTitle = await _findBestTitle(
      canonicalPlaceName,
      cityName: cityName,
    );

    if (pageTitle == null) {
      _resultCache[resultKey] = null;
      return null;
    }
    final result = await _fetchExtract(pageTitle);
    _resultCache[resultKey] = result;
    return result;
  }

  Future<String?> _findBestTitle(
    String query, {
    String? cityName,
  }) async {
    try {
      final trimmed = query.trim();
      if (trimmed.isEmpty) return null;

      final titleCacheKey = '${trimmed.toLowerCase()}|${(cityName ?? '').trim().toLowerCase()}';
      if (_titleCache.containsKey(titleCacheKey)) return _titleCache[titleCacheKey];

      final cleanCity = cityName?.trim() ?? '';

      final searchQueries = <String>[
        if (cleanCity.isNotEmpty) '$trimmed $cleanCity Egypt',
        '$trimmed Egypt',
        'Egypt $trimmed',
        trimmed,
      ];

      final scoredResults = <_ScoredWikiTitle>[];
      final seenTitles = <String>{};

      for (final q in searchQueries) {
        await _throttle();
        final response = await _dio.get(
          _apiUrl,
          queryParameters: {
            'action': 'query',
            'list': 'search',
            'srsearch': q,
            'srlimit': 8,
            'format': 'json',
            'origin': '*',
          },
        );

        final data = response.data as Map<String, dynamic>;
        final searchResults = (data['query']?['search'] as List?) ?? [];

        for (final raw in searchResults) {
          final result = raw as Map<String, dynamic>;
          final title = (result['title'] as String? ?? '').trim();
          final snippet = (result['snippet'] as String? ?? '').trim();
          if (title.isEmpty) continue;

          final normalizedTitle = _normalize(title);
          if (!seenTitles.add(normalizedTitle)) continue;

          final score = _scoreCandidate(
            query: trimmed,
            title: title,
            snippet: snippet,
            cityName: cityName,
          );

          scoredResults.add(
            _ScoredWikiTitle(title: title, score: score),
          );
        }
      }

      if (scoredResults.isEmpty) return null;

      scoredResults.sort((a, b) => b.score.compareTo(a.score));

      // لو أعلى نتيجة ضعيفة جدًا نعتبر مفيش match كويس
      if (scoredResults.first.score < 80) {
        _titleCache[titleCacheKey] = null;
        return null;
      }

      _titleCache[titleCacheKey] = scoredResults.first.title;
      return scoredResults.first.title;
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 429) {
        print('[Wikipedia] Rate limited for "$query" → skipping now');
        return null;
      }
      print('[Wikipedia] Search error for "$query": $e');
      return null;
    }
  }

  int _scoreCandidate({
    required String query,
    required String title,
    required String snippet,
    String? cityName,
  }) {
    final q = _normalize(query);
    final t = _normalize(title);
    final s = _normalize(snippet);

    int score = 0;

    if (t == q) score += 1000;
    if (t.startsWith(q)) score += 350;
    if (t.contains(q)) score += 220;

    final similarity = _similarity(q, t);
    if (similarity >= 0.96) {
      score += 400;
    } else if (similarity >= 0.92) {
      score += 260;
    } else if (similarity >= 0.88) {
      score += 140;
    }

    final qTokens = _tokens(q);
    for (final token in qTokens) {
      if (token.length < 2) continue;
      if (t.contains(token)) score += 40;
      if (s.contains(token)) score += 18;
    }

    if (cityName != null && cityName.trim().isNotEmpty) {
      final city = _normalize(cityName);
      if (t.contains(city)) score += 80;
      if (s.contains(city)) score += 45;
    }

    for (final keyword in _egyptKeywords) {
      final k = _normalize(keyword);
      if (t.contains(k)) score += 22;
      if (s.contains(k)) score += 12;
    }

    if (_looksLikePerson('$title $snippet')) {
      score -= 250;
    }

    if (_looksAbstract('$title $snippet')) {
      score -= 220;
    }

    if (_looksLikePlace(title)) {
      score += 80;
    }

    return score;
  }

  Future<WikipediaResult?> _fetchExtract(String title) async {
    try {
      await _throttle();
      final response = await _dio.get(
        _apiUrl,
        queryParameters: {
          'action': 'query',
          'titles': title,
          'prop': 'extracts|info',
          'exintro': false,
          'explaintext': true,
          'inprop': 'url',
          'format': 'json',
          'origin': '*',
        },
      );

      final data = response.data as Map<String, dynamic>;
      final pages = data['query']?['pages'] as Map<String, dynamic>? ?? {};
      if (pages.isEmpty) return null;

      final page = pages.values.first as Map<String, dynamic>;
      if (page['missing'] != null) return null;

      final fullText = (page['extract'] as String? ?? '').trim();
      if (fullText.isEmpty) return null;
      if (_looksLikePerson(fullText)) return null;
      if (_looksAbstract(fullText)) return null;

      final paragraphs = fullText
          .split('\n')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty && p.length > 40)
          .toList();

      final summary = paragraphs.isNotEmpty
          ? paragraphs.first
          : fullText.substring(
              0,
              fullText.length > 300 ? 300 : fullText.length,
            );

      final pageUrl =
          'https://en.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}';

      return WikipediaResult(
        title: (page['title'] as String? ?? title).trim(),
        summary: summary,
        fullText: fullText,
        pageUrl: pageUrl,
      );
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 429) {
        print('[Wikipedia] Rate limited while extracting "$title" → skipping now');
        return null;
      }
      print('[Wikipedia] Extract error for "$title": $e');
      return null;
    }
  }

  String extractHistorySection(String fullText) {
    const historyHeaders = [
      '== History ==',
      '=== History ===',
      '== Historical background ==',
      '=== Historical background ===',
      '== Background ==',
      '=== Background ===',
    ];

    for (final header in historyHeaders) {
      final idx = fullText.indexOf(header);
      if (idx == -1) continue;

      final afterHeaderStart = idx + header.length;
      final nextSectionIdx = fullText.indexOf('\n==', afterHeaderStart);
      final end = nextSectionIdx == -1 ? fullText.length : nextSectionIdx;

      final extracted = fullText
          .substring(afterHeaderStart, end)
          .trim()
          .replaceAll(RegExp(r'={2,}.*?={2,}'), '')
          .trim();

      if (extracted.isNotEmpty) {
        return extracted;
      }
    }

    // fallback: أول فقرتين مفيدين
    final paragraphs = fullText
        .split('\n')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && p.length > 40)
        .toList();

    if (paragraphs.length >= 2) {
      return '${paragraphs[0]}\n\n${paragraphs[1]}';
    } else if (paragraphs.isNotEmpty) {
      return paragraphs.first;
    }

    return '';
  }

  bool _looksLikePerson(String text) {
    final lower = text.toLowerCase();
    int hits = 0;
    for (final p in _personPatterns) {
      if (lower.contains(p)) hits++;
    }
    return hits >= 2 || (hits >= 1 && lower.length < 400);
  }

  bool _looksAbstract(String text) {
    final lower = text.toLowerCase();
    for (final p in _abstractPatterns) {
      if (lower.contains(p)) return true;
    }
    return false;
  }

  bool _looksLikePlace(String text) {
    final lower = text.toLowerCase();

    const placeWords = [
      'temple',
      'mosque',
      'church',
      'museum',
      'palace',
      'castle',
      'citadel',
      'fort',
      'pyramid',
      'sphinx',
      'tomb',
      'bazaar',
      'market',
      'square',
      'park',
      'garden',
      'island',
      'beach',
      'bay',
      'harbor',
      'lake',
      'valley',
      'mountain',
      'oasis',
      'desert',
      'corniche',
      'bridge',
      'hotel',
      'restaurant',
      'cafe',
      'mall',
      'library',
      'theater',
      'theatre',
      'stadium',
      'zoo',
      'aquarium',
      'tower',
      'monastery',
      'cathedral',
      'site',
      'معبد',
      'متحف',
      'قلعة',
      'هرم',
      'مسجد',
      'كنيسة',
      'قصر',
      'شاطئ',
      'فندق',
      'مطعم',
      'سوق',
      'حديقة',
    ];

    return placeWords.any((w) => lower.contains(w));
  }

  List<String> _tokens(String input) {
    return input
        .split(RegExp(r'\s+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String _normalize(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final distance = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1;
    return 1 - (distance / maxLen);
  }

  int _levenshtein(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final rows = s1.length + 1;
    final cols = s2.length + 1;
    final dist = List.generate(rows, (_) => List<int>.filled(cols, 0));

    for (int i = 0; i < rows; i++) {
      dist[i][0] = i;
    }
    for (int j = 0; j < cols; j++) {
      dist[0][j] = j;
    }

    for (int i = 1; i < rows; i++) {
      for (int j = 1; j < cols; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;

        dist[i][j] = [
          dist[i - 1][j] + 1,
          dist[i][j - 1] + 1,
          dist[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return dist[rows - 1][cols - 1];
  }
}

class _ScoredWikiTitle {
  final String title;
  final int score;

  const _ScoredWikiTitle({
    required this.title,
    required this.score,
  });
}