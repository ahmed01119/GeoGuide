class AppConfig {
  static const String geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: 'AIzaSyCUsx5OlxOiMEeBURGefvfnR1AoThJqxOA',
  );

  static const String geminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash-lite',
  );

  static bool get hasValidGeminiKey {
    return geminiApiKey.trim().isNotEmpty &&
        !geminiApiKey.contains('YOUR_') &&
        geminiApiKey.startsWith('AIza');
  }
}