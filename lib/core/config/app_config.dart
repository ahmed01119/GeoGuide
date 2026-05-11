import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String get geminiApiKey =>
      dotenv.env['GEMINI_API_KEY'] ?? '';

  static String get geminiModel =>
      dotenv.env['GEMINI_MODEL'] ?? 'gemini-2.5-flash-lite';

  static bool get hasValidGeminiKey {
    final key = geminiApiKey.trim();

    return key.isNotEmpty &&
        !key.contains('YOUR_') &&
        key.length > 20;
  }
}