class PlaceCategoryNormalizer {
  PlaceCategoryNormalizer._();

  static const List<String> allowed = [
    'tourist',
    'hotel',
    'restaurant',
    'cafe',
    'outing',
  ];

  static String normalize(String raw, {String contextText = ''}) {
    final lower = '${raw.toLowerCase()} ${contextText.toLowerCase()}';

    if (_containsAny(lower, _hotelTokens)) return 'hotel';
    if (_containsAny(lower, _restaurantTokens)) return 'restaurant';
    if (_containsAny(lower, _cafeTokens)) return 'cafe';
    if (_containsAny(lower, _outingTokens)) return 'outing';
    if (_containsAny(lower, _touristTokens)) return 'tourist';

    return 'tourist';
  }

  static bool isAllowed(String raw, {String contextText = ''}) {
    return allowed.contains(normalize(raw, contextText: contextText));
  }

  static const _hotelTokens = [
    'hotel', 'resort', 'hostel', 'guesthouse', 'guest_house', 'motel',
    'lodge', 'lodging', 'inn', 'accommodation', 'فندق', 'منتجع', 'نزل'
  ];

  static const _restaurantTokens = [
    'restaurant', 'dining', 'fast_food', 'food_court', 'grill', 'seafood',
    'steakhouse', 'eatery', 'bistro', 'مطعم', 'طعام'
  ];

  static const _cafeTokens = [
    'cafe', 'café', 'coffee', 'tea_house', 'bakery', 'patisserie',
    'كافيه', 'قهوة', 'مقهى'
  ];

  static const _outingTokens = [
    'outing', 'park', 'garden', 'zoo', 'aquarium', 'mall', 'shopping',
    'cinema', 'theater', 'theatre', 'stadium', 'amusement', 'beach',
    'leisure', 'nightlife', 'entertainment', 'activity', 'activities',
    'hangout', 'fun', 'خروجات', 'فسح', 'فسحة', 'ترفيه', 'حديقة', 'شاطئ',
    'ملاهي', 'تسوق'
  ];

  static const _touristTokens = [
    'tourist', 'attraction', 'landmark', 'monument', 'historic', 'museum',
    'temple', 'mosque', 'church', 'palace', 'castle', 'citadel', 'fort',
    'pyramid', 'tomb', 'ruins', 'archaeological', 'gallery', 'viewpoint',
    'heritage', 'sight', 'معلم', 'متحف', 'معبد', 'مسجد', 'كنيسة', 'قلعة',
    'هرم', 'آثار'
  ];

  static bool _containsAny(String text, List<String> tokens) {
    for (final token in tokens) {
      if (text.contains(token)) return true;
    }
    return false;
  }
}
