import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ChatbotService {
  /// Chatbot API Space
  /// Expected endpoint: /chat
  static const String _chatbotApiBaseUrl =
      "https://geoguide-organization-geoguide-api.hf.space";

  /// RAG / Places API Space
  /// Expected endpoint: /api/ask
  static const String _ragApiBaseUrl =
      "https://geoguide-organization-geoguide-chatbot-api.hf.space";


  static const Duration _shortTimeout = Duration(seconds: 35);
  static const Duration _longTimeout = Duration(seconds: 240);

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

    /// مهم جدًا للـ deployment:
    /// Hugging Face Space ممكن يكون نايم، فبنحاول نصحي السيرفر الأول.
    await _warmUpServices();

    /// 1) Try Chatbot API first
    try {
      final answer = await _askChatbotApi(clean);

      if (answer.trim().isNotEmpty) {
        debugPrint('✅ Answer source: Chatbot API');

        return ChatbotResponse(
          answer: answer,
          responseTimeSec: _elapsedSeconds(start),
          source: ChatbotSource.newAi,
        );
      }

      throw Exception('Chatbot API returned empty answer');
    } catch (e) {
      debugPrint('⚠️ Chatbot API failed. Switching to RAG fallback...');
      debugPrint('Chatbot API error: $e');
    }

    /// 2) Try RAG API fallback
    try {
      final fallbackAnswer = await _askRagApi(clean);

      if (fallbackAnswer.trim().isNotEmpty) {
        debugPrint('✅ Answer source: RAG API fallback');

        return ChatbotResponse(
          answer: fallbackAnswer,
          responseTimeSec: _elapsedSeconds(start),
          source: ChatbotSource.ragFallback,
        );
      }

      throw Exception('RAG API returned empty answer');
    } catch (e) {
      debugPrint('❌ RAG API fallback failed: $e');

      return ChatbotResponse(
        answer: 'Could not connect to AI services. Please try again later.',
        responseTimeSec: _elapsedSeconds(start),
        source: ChatbotSource.error,
      );
    }
  }

  Future<String> _askChatbotApi(String question) async {
    /// الأساسي المتوقع للـ chatbot-api
    try {
      final data = await _postJson(
        url: '$_chatbotApiBaseUrl/chat',
        body: {
          'question': question,
        },
        timeout: _longTimeout,
      );

      return _formatAnyAiResponse(data);
    } catch (e) {
      debugPrint('⚠️ /chat failed on chatbot API: $e');
    }

    /// fallback احتياطي لو السيرفر عنده endpoint مختلف
    final data = await _postJson(
      url: '$_chatbotApiBaseUrl/api/ask',
      body: {
        'question': question,
      },
      timeout: _longTimeout,
    );

    return _formatAnyAiResponse(data);
  }

  Future<String> _askRagApi(String question) async {
    /// الأساسي المتوقع للـ rag-api
    try {
      final data = await _postJson(
        url: '$_ragApiBaseUrl/api/ask',
        body: {
          'question': question,
        },
        timeout: _longTimeout,
      );

      return _formatAnyAiResponse(data);
    } catch (e) {
      debugPrint('⚠️ /api/ask failed on RAG API: $e');
    }

    /// fallback احتياطي لو السيرفر عنده endpoint /chat
    final data = await _postJson(
      url: '$_ragApiBaseUrl/chat',
      body: {
        'question': question,
      },
      timeout: _longTimeout,
    );

    return _formatAnyAiResponse(data);
  }

  Future<Map<String, dynamic>> _postJson({
    required String url,
    required Map<String, dynamic> body,
    required Duration timeout,
  }) async {
    debugPrint('➡️ POST $url');

    final response = await http
        .post(
          Uri.parse(url),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);

    debugPrint('⬅️ Status: ${response.statusCode} from $url');

    if (response.statusCode != 200) {
      throw Exception(
        'Server error: ${response.statusCode} | ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is Map<String, dynamic>) {
      if (decoded['error'] != null) {
        throw Exception(
          'API error: ${decoded['error']} ${decoded['details'] ?? ''}',
        );
      }

      return decoded;
    }

    throw Exception('Invalid response format: ${response.body}');
  }

  Future<void> _warmUpServices() async {
    await Future.wait([
      _warmUpUrl('$_chatbotApiBaseUrl/health'),
      _warmUpUrl(_chatbotApiBaseUrl),
      _warmUpUrl('$_ragApiBaseUrl/health'),
      _warmUpUrl(_ragApiBaseUrl),
    ]);
  }

  Future<void> _warmUpUrl(String url) async {
    try {
      debugPrint('🔥 Warming up: $url');

      await http
          .get(
            Uri.parse(url),
            headers: const {
              'Accept': 'application/json',
            },
          )
          .timeout(_shortTimeout);
    } catch (e) {
      /// مش هنوقف السؤال لو warm-up فشل
      debugPrint('Warm-up ignored for $url: $e');
    }
  }

  String _formatAnyAiResponse(Map<String, dynamic> data) {
    /// common format:
    /// { "answer": "..." }
    if (data['answer'] != null) {
      final answer = data['answer'].toString().trim();
      if (answer.isNotEmpty) return answer;
    }

    /// another possible format:
    /// { "response": "..." }
    if (data['response'] != null) {
      final response = data['response'].toString().trim();
      if (response.isNotEmpty) return response;
    }

    /// another possible format:
    /// { "message": "..." }
    if (data['message'] != null) {
      final message = data['message'].toString().trim();
      if (message.isNotEmpty) return message;
    }

    /// structured landmark format:
    /// {
    ///   "title": "...",
    ///   "location": "...",
    ///   "content": "...",
    ///   "historical_facts": [],
    ///   "travel_tips": []
    /// }
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

    if (title.trim().isNotEmpty) {
      buffer.writeln('🏛️ ${title.trim()}');
      buffer.writeln();
    }

    if (location.trim().isNotEmpty) {
      buffer.writeln('📍 Location: ${location.trim()}');
      buffer.writeln();
    }

    if (content.trim().isNotEmpty) {
      buffer.writeln(content.trim());
      buffer.writeln();
    }

    if (historicalFacts.isNotEmpty) {
      buffer.writeln('📚 Historical Facts:');
      for (final fact in historicalFacts) {
        final cleanFact = fact.trim();
        if (cleanFact.isNotEmpty) {
          buffer.writeln('• $cleanFact');
        }
      }
      buffer.writeln();
    }

    if (travelTips.isNotEmpty) {
      buffer.writeln('💡 Travel Tips:');
      for (final tip in travelTips) {
        final cleanTip = tip.trim();
        if (cleanTip.isNotEmpty) {
          buffer.writeln('• $cleanTip');
        }
      }
    }

    final result = buffer.toString().trim();

    if (result.isEmpty) {
      throw Exception('AI response format is empty: $data');
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