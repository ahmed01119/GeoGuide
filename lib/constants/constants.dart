// ============================================================
//  core/constants.dart
//  App-wide constants
// ============================================================

class AppConstants {
  const AppConstants._();

  // ── Optional free AI config ────────────────────────────────
  static const String geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );

  // ── Free source toggles ────────────────────────────────────
  static const bool enableWikipedia = true;
  static const bool enableWikimedia = true;
  static const bool enablePexels = true;
  static const bool enableUnsplashFallback = true;
  static const bool enableOverpass = true;
  static const bool enableGeminiFallback = true;

  // ── Cache / refresh TTLs ───────────────────────────────────
  static const Duration wikiTtl = Duration(days: 30);
  static const Duration imagesTtl = Duration(days: 14);
  static const Duration nearbyTtl = Duration(hours: 6);
  static const Duration searchCacheTtl = Duration(minutes: 10);

  // ── Canonical categories used across the app ───────────────
  static const List<String> allowedPlaceCategories = [
    'tourist',
    'hotel',
    'restaurant',
    'cafe',
    'outing',
  ];

  // ── Nearby categories used in nearby service / free APIs ───
  static const List<String> supportedNearbyCategories = [
    'hotel',
    'restaurant',
    'cafe',
    'attraction',
  ];

  // ── Egypt city coordinates for seeding ─────────────────────
  static const List<Map<String, dynamic>> egyptCities = [
    {'name': 'Cairo', 'lat': 30.0444, 'lng': 31.2357},
    {'name': 'Luxor', 'lat': 25.6872, 'lng': 32.6396},
    {'name': 'Aswan', 'lat': 24.0889, 'lng': 32.8998},
    {'name': 'Alexandria', 'lat': 31.2001, 'lng': 29.9187},
    {'name': 'Giza', 'lat': 29.9870, 'lng': 31.2118},
    {'name': 'Hurghada', 'lat': 27.2578, 'lng': 33.8116},
    {'name': 'Sharm El Sheikh', 'lat': 27.9158, 'lng': 34.3300},
    {'name': 'Dahab', 'lat': 28.4897, 'lng': 34.5093},
    {'name': 'Siwa', 'lat': 29.2032, 'lng': 25.5197},
  ];

  // ── Search defaults ────────────────────────────────────────
  static const int defaultSearchMaxResults = 10;
  static const int defaultSuggestionsCount = 6;
  static const int defaultGalleryCount = 7;
}