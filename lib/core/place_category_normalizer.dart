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
    'hotel', 'hotels', 'resort', 'hostel', 'guesthouse', 'guest_house',
    'motel', 'lodge', 'lodging', 'inn', 'accommodation',
    'فندق', 'فنادق', 'اوتيل', 'أوتيل', 'منتجع', 'نزل'
  ];

  static const _restaurantTokens = [
    'restaurant', 'restaurants', 'dining', 'fast_food', 'food_court',
    'grill', 'seafood', 'steakhouse', 'eatery', 'bistro', 'food', 'eat',
    'مطعم', 'مطاعم', 'طعام', 'اكل', 'أكل', 'مشويات', 'سمك'
  ];

  static const _cafeTokens = [
    'cafe', 'cafes', 'café', 'coffee', 'tea_house', 'bakery',
    'patisserie', 'cafeteria', 'caffe',
    'كافيه', 'كافيهات', 'كافتريا', 'كافيتريا', 'كافترية',
    'كوفي', 'قهوة', 'مقهى', 'مقهي'
  ];

  static const _outingTokens = [
    'outing', 'outings', 'park', 'garden', 'zoo', 'aquarium', 'mall',
    'shopping', 'cinema', 'theater', 'theatre', 'stadium', 'amusement',
    'beach', 'leisure', 'nightlife', 'entertainment', 'activity',
    'activities', 'hangout', 'fun',
    'خروجات', 'خروجة', 'فسح', 'فسحة', 'ترفيه', 'حديقة', 'حدائق',
    'شاطئ', 'ملاهي', 'تسوق', 'مول', 'سينما'
  ];

  static const _touristTokens = [
    'tourist', 'attraction', 'landmark', 'monument', 'historic', 'historical',
    'museum', 'temple', 'mosque', 'church', 'palace', 'castle', 'citadel',
    'fort', 'pyramid', 'tomb', 'ruins', 'archaeological',
    'archaeological site', 'heritage', 'valley', 'necropolis', 'burial',
    'gallery', 'viewpoint', 'sight',
    'مزار', 'معلم', 'متحف', 'معبد', 'مسجد', 'جامع', 'كنيسة', 'قلعة',
    'هرم', 'اهرام', 'أهرام', 'آثار', 'اثار', 'وادي', 'مقابر'
  ];

  static bool _containsAny(String text, List<String> tokens) {
    for (final token in tokens) {
      if (text.contains(token)) return true;
    }
    return false;
  }
}
