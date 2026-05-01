class PlaceValidator {
  // ── Allowed FINAL categories ───────────────────────────────
  static const allowedCategories = [
    'tourist',
    'hotel',
    'restaurant',
    'cafe',
    'outing',
  ];

  // ── keywords mapping ───────────────────────────────────────
  static const _categoryMap = {
    'tourist': [
      'tourist', 'attraction', 'landmark', 'monument', 'historic',
      'museum', 'temple', 'mosque', 'church', 'palace', 'castle',
      'citadel', 'fort', 'pyramid', 'tomb', 'ruins',
    ],
    'hotel': [
      'hotel', 'resort', 'hostel', 'guesthouse', 'lodging'
    ],
    'restaurant': [
      'restaurant', 'dining', 'eat', 'grill', 'seafood', 'food'
    ],
    'cafe': [
      'cafe', 'coffee', 'tea', 'bakery'
    ],
    'outing': [
      'park', 'garden', 'zoo', 'beach', 'mall',
      'cinema', 'theater', 'stadium', 'market'
    ],
  };

  // ── Reject patterns ────────────────────────────────────────
  static const _rejectPatterns = [
    'was born', 'he is', 'she is',
    'actor', 'actress', 'footballer',
    'politician', 'singer',
    'company', 'bank', 'university',
    'school', 'hospital', 'clinic',
    'list of', 'category:', 'disambiguation',
  ];

  // ════════════════════════════════════════════════════════════
  //  PUBLIC API
  // ════════════════════════════════════════════════════════════

  static bool isValidPlace({
    required String name,
    required String description,
    required String category, required String city,
  }) {
    final nameLower = name.toLowerCase();
    final descLower = description.toLowerCase();

    // ── reject unwanted ─────────────────────────────
    for (final p in _rejectPatterns) {
      if (nameLower.contains(p) || descLower.contains(p)) {
        return false;
      }
    }

    // ── must be meaningful place ────────────────────
    if (description.trim().length < 30) return false;

    // ── must match allowed category ────────────────
    final normalized = _normalizeCategory(category, name, description);

    if (!allowedCategories.contains(normalized)) {
      return false;
    }

    return true;
  }

  // ───────────────────────────────────────────────
  // CATEGORY NORMALIZATION
  // ───────────────────────────────────────────────
  static String _normalizeCategory(
    String raw,
    String name,
    String description,
  ) {
    final text =
        '${raw.toLowerCase()} ${name.toLowerCase()} ${description.toLowerCase()}';

    for (final entry in _categoryMap.entries) {
      for (final keyword in entry.value) {
        if (text.contains(keyword)) {
          return entry.key;
        }
      }
    }

    return 'tourist'; // default fallback
  }

  // ───────────────────────────────────────────────
  // Wikipedia validation
  // ───────────────────────────────────────────────
  static bool isValidWikipediaResult({
    required String title,
    required String extract, required String description,
  }) {
    final lower = extract.toLowerCase();

    // reject people
    if (lower.contains('was born') ||
        lower.contains('he is') ||
        lower.contains('she is')) {
      return false;
    }

    // reject abstract topics
    if (lower.contains('history of') ||
        lower.contains('ancient egypt')) {
      return false;
    }

    return true;
  }
}