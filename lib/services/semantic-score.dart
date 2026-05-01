// ============================================================
//  services/semantic_scorer.dart
//
//  Lightweight semantic scoring engine.
//  Ranks landmarks by semantic relevance to a search query
//  without requiring heavy ML embeddings — uses weighted
//  token matching, alias expansion, fuzzy similarity,
//  and context-aware ranking.
// ============================================================

import 'package:geoguide/models.dart/landmark_model.dart';

class SemanticScore {
  final Landmark landmark;
  final double score;
  final String matchReason;

  const SemanticScore({
    required this.landmark,
    required this.score,
    required this.matchReason,
  });
}

class SemanticScorer {
  // ── Semantic synonym groups (expand matching coverage) ─────
  static const Map<String, List<String>> _synonymGroups = {
    'pyramid': ['pyramid', 'pyramids', 'haram', 'أهرام', 'هرم'],
    'temple': ['temple', 'معبد', 'sanctuary', 'shrine'],
    'mosque': ['mosque', 'مسجد', 'جامع', 'islamic'],
    'church': ['church', 'كنيسة', 'cathedral', 'coptic'],
    'museum': ['museum', 'متحف', 'gallery', 'exhibition'],
    'market': ['market', 'bazaar', 'souk', 'سوق', 'خان'],
    'beach': ['beach', 'شاطئ', 'coast', 'seafront', 'corniche', 'كورنيش'],
    'hotel': [
      'hotel',
      'فندق',
      'resort',
      'منتجع',
      'accommodation',
      'stay',
      'lodge'
    ],
    'restaurant': [
      'restaurant',
      'مطعم',
      'food',
      'dining',
      'eat',
      'أكل',
      'cuisine'
    ],
    'cafe': ['cafe', 'كافيه', 'coffee', 'قهوة', 'tea'],
    'park': ['park', 'حديقة', 'garden', 'zoo'],
    'island': ['island', 'جزيرة', 'isle'],
    'fort': ['fort', 'fortress', 'citadel', 'قلعة', 'castle'],
    'palace': ['palace', 'قصر', 'mansion'],
    'tomb': ['tomb', 'مقبرة', 'burial', 'necropolis', 'mausoleum'],
    'library': ['library', 'مكتبة'],
    'ancient': [
      'ancient',
      'قديم',
      'pharaonic',
      'فرعوني',
      'historic',
      'archaeological',
      'تاريخي',
      'أثري'
    ],
    'roman': ['roman', 'روماني', 'greco-roman'],
    'nile': ['nile', 'نيل', 'river', 'نهر'],
    'red sea': ['red sea', 'البحر الأحمر', 'coral', 'reef', 'diving', 'snorkel'],
    'mediterranean': ['mediterranean', 'البحر الأبيض', 'sea'],
    'outing': [
      'outing',
      'hangout',
      'fun',
      'activity',
      'activities',
      'nightlife',
      'mall',
      'cinema',
      'walk',
      'family',
      'kids',
      'خروجات',
      'فسح',
      'ترفيه'
    ],
  };

  // ── City name normalization ─────────────────────────────────
  static const Map<String, String> _cityNormalization = {
    'cairo': 'Cairo',
    'القاهرة': 'Cairo',
    'al qahira': 'Cairo',
    'giza': 'Giza',
    'الجيزة': 'Giza',
    'luxor': 'Luxor',
    'الأقصر': 'Luxor',
    'louxor': 'Luxor',
    'aswan': 'Aswan',
    'أسوان': 'Aswan',
    'alexandria': 'Alexandria',
    'alex': 'Alexandria',
    'الإسكندرية': 'Alexandria',
    'اسكندرية': 'Alexandria',
    'hurghada': 'Hurghada',
    'الغردقة': 'Hurghada',
    'hurgada': 'Hurghada',
    'sharm': 'Sharm El Sheikh',
    'شرم': 'Sharm El Sheikh',
    'sharm el sheikh': 'Sharm El Sheikh',
    'dahab': 'Dahab',
    'دهب': 'Dahab',
    'siwa': 'Siwa',
    'سيوة': 'Siwa',
  };

  // ── Field weights for scoring ───────────────────────────────
  static const double _nameWeight = 10.0;
  static const double _shortDescWeight = 4.0;
  static const double _fullDescWeight = 2.0;
  static const double _historyWeight = 1.5;
  static const double _categoryWeight = 6.0;
  static const double _cityWeight = 5.0;
  static const double _addressWeight = 3.0;

  // ════════════════════════════════════════════════════════════
  //  PUBLIC API
  // ════════════════════════════════════════════════════════════

  /// Rank a list of landmarks by semantic relevance to query.
  /// Returns landmarks sorted by score (highest first), filtered
  /// to only include those with score > minScore.
  static List<SemanticScore> rank({
    required String query,
    required List<Landmark> landmarks,
    String? cityHint,
    String? categoryHint,
    List<String> semanticKeywords = const [],
    double minScore = 0,
  }) {
    if (query.trim().isEmpty && semanticKeywords.isEmpty) {
      final fallback = landmarks
          .map(
            (lm) => SemanticScore(
              landmark: lm,
              score: _qualityBonus(lm),
              matchReason: 'quality ranking',
            ),
          )
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));
      return fallback;
    }

    final tokens = _tokenize(query);
    final expandedTokens = _expandWithSynonyms(tokens);
    final allTokens = {
      ...tokens,
      ...expandedTokens,
      ...semanticKeywords.map(_norm).where((e) => e.isNotEmpty),
    };

    final normalizedCity = cityHint != null ? _normalizeCity(cityHint) : null;
    final normalizedCategoryHint =
        categoryHint != null ? _normalizeCategory(categoryHint) : null;

    final scores = <SemanticScore>[];

    for (final lm in landmarks) {
      final result = _scoreLandmark(
        landmark: lm,
        queryTokens: allTokens,
        originalQuery: query,
        cityHint: normalizedCity,
        categoryHint: normalizedCategoryHint,
      );

      if (result.score > minScore) {
        scores.add(result);
      }
    }

    scores.sort((a, b) {
      final diff = b.score - a.score;
      if (diff.abs() < 0.01) {
        return _qualityBonus(b.landmark).compareTo(_qualityBonus(a.landmark));
      }
      return diff > 0 ? 1 : -1;
    });

    return scores;
  }

  /// Score a single landmark against a query.
  static SemanticScore scoreSingle({
    required String query,
    required Landmark landmark,
    List<String> semanticKeywords = const [],
  }) {
    final tokens = _tokenize(query);
    final expanded = _expandWithSynonyms(tokens);
    final allTokens = {
      ...tokens,
      ...expanded,
      ...semanticKeywords.map(_norm).where((e) => e.isNotEmpty),
    };

    return _scoreLandmark(
      landmark: landmark,
      queryTokens: allTokens,
      originalQuery: query,
      cityHint: null,
      categoryHint: null,
    );
  }

  // ════════════════════════════════════════════════════════════
  //  CORE SCORING
  // ════════════════════════════════════════════════════════════

  static SemanticScore _scoreLandmark({
    required Landmark landmark,
    required Set<String> queryTokens,
    required String originalQuery,
    String? cityHint,
    String? categoryHint,
  }) {
    double score = 0;
    final reasons = <String>[];

    final normQuery = _norm(originalQuery);
    final normName = _norm(landmark.name);

    if (normQuery.isNotEmpty) {
      // ── Exact name match (highest priority) ──────────────────
      if (normName == normQuery) {
        score += _nameWeight * 15;
        reasons.add('exact name match');
      } else if (normName.contains(normQuery) && normQuery.length > 3) {
        score += _nameWeight * 8;
        reasons.add('name contains query');
      } else if (normQuery.contains(normName) && normName.length > 3) {
        score += _nameWeight * 6;
        reasons.add('query contains name');
      }
    }

    // ── Token matching across all fields ─────────────────────
    score += _tokenScoreField(queryTokens, normName, _nameWeight, reasons, 'name');
    score += _tokenScoreField(
      queryTokens,
      _norm(landmark.shortDescription),
      _shortDescWeight,
      reasons,
      'shortDesc',
    );
    score += _tokenScoreField(
      queryTokens,
      _norm(landmark.fullDescription),
      _fullDescWeight,
      reasons,
      'fullDesc',
    );
    score += _tokenScoreField(
      queryTokens,
      _norm(landmark.history),
      _historyWeight,
      reasons,
      'history',
    );
    score += _tokenScoreField(
      queryTokens,
      _norm(landmark.address),
      _addressWeight,
      reasons,
      'address',
    );

    // ── Category match ────────────────────────────────────────
    final normCategory = _normalizeCategory(landmark.category);
    final catScore = _tokenScoreField(
      queryTokens,
      normCategory,
      _categoryWeight,
      reasons,
      'category',
    );
    score += catScore;

    // ── City match ────────────────────────────────────────────
    if (cityHint != null) {
      final normCity = _norm(landmark.city);
      final normHint = _norm(cityHint);
      if (normCity.contains(normHint) || normHint.contains(normCity)) {
        score += _cityWeight * 3;
        reasons.add('city match: ${landmark.city}');
      } else {
        score *= 0.4;
        reasons.add('city mismatch penalty');
      }
    } else {
      final normCity = _norm(landmark.city);
      if (queryTokens.any((t) => normCity.contains(t) && t.length > 3)) {
        score += _cityWeight;
        reasons.add('city from query: ${landmark.city}');
      }
    }

    // ── Category hint boost ───────────────────────────────────
    if (categoryHint != null && categoryHint.isNotEmpty) {
      if (_categoryMatchesHint(normCategory, categoryHint)) {
        score += _categoryWeight * 2;
        reasons.add('category hint match');
      }
    }

    // ── Fuzzy name similarity ─────────────────────────────────
    final sim = _similarity(normQuery, normName);
    if (sim >= 0.90) {
      score += _nameWeight * 5;
      reasons.add('high fuzzy similarity: ${(sim * 100).round()}%');
    } else if (sim >= 0.78) {
      score += _nameWeight * 2;
      reasons.add('fuzzy similarity: ${(sim * 100).round()}%');
    } else if (sim >= 0.65) {
      score += _nameWeight * 0.5;
    }

    // ── Quality bonus ─────────────────────────────────────────
    score += _qualityBonus(landmark) * 0.2;

    // ── Importance bonus ──────────────────────────────────────
    score += _importanceBonus(landmark) * 0.3;

    return SemanticScore(
      landmark: landmark,
      score: score,
      matchReason: reasons.isNotEmpty ? reasons.join(', ') : 'no strong match',
    );
  }

  static double _tokenScoreField(
    Set<String> queryTokens,
    String fieldValue,
    double weight,
    List<String> reasons,
    String fieldName,
  ) {
    if (fieldValue.isEmpty || queryTokens.isEmpty) return 0;

    double score = 0;
    int hits = 0;

    for (final token in queryTokens) {
      if (token.length < 2) continue;
      if (_isGenericToken(token)) continue;

      if (fieldValue.contains(token)) {
        final lengthBonus = token.length >= 6
            ? 2.0
            : token.length >= 4
                ? 1.5
                : 1.0;
        score += weight * lengthBonus;
        hits++;
      }
    }

    if (hits >= 2) score *= 1.3;
    if (hits >= 3) score *= 1.5;

    if (hits > 0) reasons.add('$fieldName tokens: $hits hits');
    return score;
  }

  // ════════════════════════════════════════════════════════════
  //  SYNONYM EXPANSION
  // ════════════════════════════════════════════════════════════

  static Set<String> _expandWithSynonyms(Set<String> tokens) {
    final expanded = <String>{};

    for (final token in tokens) {
      for (final group in _synonymGroups.values) {
        if (group.any((s) => _norm(s) == token || _norm(s).contains(token))) {
          for (final synonym in group) {
            expanded.addAll(_tokenize(synonym));
          }
        }
      }
    }

    return expanded;
  }

  // ════════════════════════════════════════════════════════════
  //  QUALITY & IMPORTANCE BONUSES
  // ════════════════════════════════════════════════════════════

  static double _qualityBonus(Landmark lm) {
    double bonus = 0;
    bonus += lm.rating * 3;
    if (lm.imageUrl.trim().isNotEmpty) bonus += 2;
    bonus += lm.mediaUrls.length * 0.5;
    if (lm.shortDescription.trim().length > 50) bonus += 2;
    if (lm.fullDescription.trim().length > 200) bonus += 3;
    if (lm.wikipediaUrl != null && lm.wikipediaUrl!.trim().isNotEmpty) {
      bonus += 2;
    }
    return bonus;
  }

  static double _importanceBonus(Landmark lm) {
    double bonus = 0;
    final name = lm.name.toLowerCase();

    const famousKeywords = [
      'pyramid',
      'sphinx',
      'karnak',
      'valley of the kings',
      'abu simbel',
      'philae',
      'egyptian museum',
      'grand egyptian museum',
      'khan el-khalili',
      'bibliotheca',
      'qaitbay',
      'citadel',
      'hatshepsut',
      'colossi',
    ];

    for (final kw in famousKeywords) {
      if (name.contains(kw)) {
        bonus += 15;
        break;
      }
    }

    final cat = _normalizeCategory(lm.category);
    if (cat == 'tourist') bonus += 5;
    if (cat.contains('museum') ||
        cat.contains('temple') ||
        cat.contains('pyramid')) {
      bonus += 8;
    }
    if (cat == 'hotel') bonus += 2;
    if (cat == 'restaurant') bonus += 1.5;
    if (cat == 'cafe') bonus += 1;
    if (cat == 'outing') bonus += 2;

    return bonus;
  }

  // ════════════════════════════════════════════════════════════
  //  TEXT UTILITIES
  // ════════════════════════════════════════════════════════════

  static String _norm(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^\w\u0600-\u06FF\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Set<String> _tokenize(String input) {
    const stopWords = {
      'in',
      'at',
      'near',
      'the',
      'a',
      'an',
      'of',
      'with',
      'for',
      'and',
      'or',
      'is',
      'was',
      'are',
      'be',
      'to',
      'from',
      'by',
      'its',
      'it',
      'this',
      'that',
      'on',
      'as',
      'el',
      'al',
      'de',
      'في',
      'من',
      'إلى',
      'على',
      'مع',
      'عند',
      'هو',
      'هي',
      'ما',
    };

    return _norm(input)
        .split(RegExp(r'\s+'))
        .map((w) => w.trim())
        .where((w) => w.length >= 2 && !stopWords.contains(w))
        .toSet();
  }

  static String _normalizeCity(String city) {
    final lower = city.trim().toLowerCase();
    return _cityNormalization[lower] ?? city.trim();
  }

  static String _normalizeCategory(String category) {
    final lower = _norm(category);

    if (lower.contains('hotel') || lower.contains('resort')) return 'hotel';
    if (lower.contains('restaurant') || lower.contains('food')) {
      return 'restaurant';
    }
    if (lower.contains('cafe') || lower.contains('coffee')) return 'cafe';
    if (lower.contains('outing') ||
        lower.contains('park') ||
        lower.contains('mall') ||
        lower.contains('cinema') ||
        lower.contains('nightlife')) {
      return 'outing';
    }

    return lower;
  }

  static bool _categoryMatchesHint(String normCategory, String hint) {
    final normalizedHint = _normalizeCategory(hint);

    if (normCategory.contains(normalizedHint) ||
        normalizedHint.contains(normCategory)) {
      return true;
    }

    if (normalizedHint == 'outing') {
      return normCategory.contains('outing') ||
          normCategory.contains('park') ||
          normCategory.contains('mall') ||
          normCategory.contains('cinema');
    }

    if (normalizedHint == 'tourist') {
      return normCategory.contains('tourist') ||
          normCategory.contains('museum') ||
          normCategory.contains('temple') ||
          normCategory.contains('historic') ||
          normCategory.contains('landmark');
    }

    return false;
  }

  static bool _isGenericToken(String token) {
    const generic = {
      'egypt',
      'place',
      'places',
      'thing',
      'things',
      'visit',
      'visiting',
      'trip',
      'travel',
      'best',
      'good',
    };
    return generic.contains(token);
  }

  static double _similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final dist = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    return 1.0 - (dist / maxLen);
  }

  static int _levenshtein(String s1, String s2) {
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