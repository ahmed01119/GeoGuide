class AppConfig {
  const AppConfig._();

  static const String geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  static const String geminiModel =
      String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-2.5-flash');

  static bool get hasValidGeminiKey {
    final key = geminiApiKey.trim();
    return key.isNotEmpty && key.startsWith('AIza');
  }
}
