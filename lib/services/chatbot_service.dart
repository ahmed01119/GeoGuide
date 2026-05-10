import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ChatbotService {
  static const String _newAiBaseUrl =
      "https://geoguide-organization-geoguide-api.hf.space";

  static const String _ragAiBaseUrl =
      "https://geoguide-organization-geoguide-chatbot-api.hf.space";

  Future<ChatbotResponse> ask(String question) async {
    final clean = question.trim();

    if (clean.isEmpty) {
      return const ChatbotResponse(
        answer: 'Please write a question first.',
        responseTimeSec: 0,
        source: ChatbotSource.none,
      );
    }

    final start = DateTime.now();

    // 1) Try New AI first
    try {
      final answer = await _askNewAi(clean);

      if (answer.trim().isNotEmpty) {
        debugPrint('✅ Answer source: New AI');

        return ChatbotResponse(
          answer: answer,
          responseTimeSec: _elapsedSeconds(start),
          source: ChatbotSource.newAi,
        );
      }

      throw Exception('New AI returned empty answer');
    } catch (e) {
      debugPrint('⚠️ New AI failed. Switching to RAG fallback...');
      debugPrint('New AI error: $e');
    }

    // 2) If New AI fails, use RAG fallback
    try {
      await _warmUpRag();

      final fallbackResponse = await _askRagFallback(clean);

      if (fallbackResponse.answer.trim().isNotEmpty) {
        debugPrint('✅ Answer source: RAG fallback');

        return fallbackResponse.copyWith(
          source: ChatbotSource.ragFallback,
          responseTimeSec: fallbackResponse.responseTimeSec == 0
              ? _elapsedSeconds(start)
              : fallbackResponse.responseTimeSec,
        );
      }

      throw Exception('RAG returned empty answer');
    } catch (e) {
      debugPrint('❌ RAG fallback failed: $e');

      return ChatbotResponse(
        answer: 'Could not connect to AI services. Please try again later.',
        responseTimeSec: _elapsedSeconds(start),
        source: ChatbotSource.error,
      );
    }
  }

  Future<String> _askNewAi(String question) async {
    final response = await http
        .post(
          Uri.parse('$_newAiBaseUrl/api/ask'),
          headers: const {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'question': question,
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      throw Exception(
        'New AI server error: ${response.statusCode} | ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    return _formatNewAiResponse(data);
  }

  Future<ChatbotResponse> _askRagFallback(String question) async {
    final response = await http
        .post(
          Uri.parse('$_ragAiBaseUrl/chat'),
          headers: const {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'question': question,
          }),
        )
        .timeout(const Duration(seconds: 240));

    if (response.statusCode != 200) {
      throw Exception(
        'RAG fallback server error: ${response.statusCode} | ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (data['error'] != null) {
      throw Exception(
        'RAG API error: ${data['error']} ${data['details'] ?? ''}',
      );
    }

    return ChatbotResponse(
      answer: (data['answer'] ?? 'No answer found.').toString(),
      responseTimeSec: ((data['response_time_sec'] ?? 0) as num).toDouble(),
      source: ChatbotSource.ragFallback,
    );
  }

  Future<void> _warmUpRag() async {
    try {
      await http
          .get(Uri.parse('$_ragAiBaseUrl/health'))
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      // Ignore warm-up errors and continue to /chat
    }
  }

  String _formatNewAiResponse(Map<String, dynamic> data) {
    if (data['answer'] != null) {
      final answer = data['answer'].toString().trim();
      if (answer.isNotEmpty) return answer;
    }

    final title = data['title']?.toString() ?? '';
    final location = data['location']?.toString() ?? '';
    final content = data['content']?.toString() ?? '';

    final historicalFacts = (data['historical_facts'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final travelTips = (data['travel_tips'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final buffer = StringBuffer();

    if (title.isNotEmpty) {
      buffer.writeln('🏛️ $title');
      buffer.writeln();
    }

    if (location.isNotEmpty) {
      buffer.writeln('📍 Location: $location');
      buffer.writeln();
    }

    if (content.isNotEmpty) {
      buffer.writeln(content);
      buffer.writeln();
    }

    if (historicalFacts.isNotEmpty) {
      buffer.writeln('📚 Historical Facts:');
      for (final fact in historicalFacts) {
        buffer.writeln('• $fact');
      }
      buffer.writeln();
    }

    if (travelTips.isNotEmpty) {
      buffer.writeln('💡 Travel Tips:');
      for (final tip in travelTips) {
        buffer.writeln('• $tip');
      }
    }

    final result = buffer.toString().trim();

    if (result.isEmpty) {
      throw Exception('New AI response format is empty');
    }

    return result;
  }

  double _elapsedSeconds(DateTime start) {
    return DateTime.now().difference(start).inMilliseconds / 1000.0;
  }
}

enum ChatbotSource {
  none,
  newAi,
  ragFallback,
  oldFlaskFallback,
  error,
}

class ChatbotResponse {
  final String answer;
  final double responseTimeSec;
  final ChatbotSource source;

  const ChatbotResponse({
    required this.answer,
    required this.responseTimeSec,
    required this.source,
  });

  ChatbotResponse copyWith({
    String? answer,
    double? responseTimeSec,
    ChatbotSource? source,
  }) {
    return ChatbotResponse(
      answer: answer ?? this.answer,
      responseTimeSec: responseTimeSec ?? this.responseTimeSec,
      source: source ?? this.source,
    );
  }
}