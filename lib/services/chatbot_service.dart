import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ChatbotService {
  // غيري ده لـ IPv4 بتاع اللابتوب لو هتشغلي على موبايل حقيقي
  // static const String _laptopIp = '192.168.1.6';

  // static String get _newAiBaseUrl {
  //   if (kIsWeb) return 'http://localhost:3000';

  //   // Android Emulator:
  //   return 'http://10.0.2.2:3000';

  //   // Real phone:
  //   // return 'http://$_laptopIp:3000';
  // }

static const String _newAiBaseUrl =
    "https://mostafa1249687-geoguide-api.hf.space";

  static String get _oldFlaskBaseUrl {
    if (kIsWeb) return 'http://localhost:1234';

    // Android Emulator:
    return 'http://10.0.2.2:1234';

    // Real phone:
    // return 'http://$_laptopIp:1234';
  }



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

    try {
      final answer = await _askNewAi(clean);

      return ChatbotResponse(
        answer: answer,
        responseTimeSec: _elapsedSeconds(start),
        source: ChatbotSource.newAi,
      );
    } catch (_) {
      try {
        final oldResponse = await _askOldFlask(clean);
        return oldResponse.copyWith(
          source: ChatbotSource.oldFlaskFallback,
          responseTimeSec: oldResponse.responseTimeSec == 0
              ? _elapsedSeconds(start)
              : oldResponse.responseTimeSec,
        );
      } catch (e) {
        return const ChatbotResponse(
          answer:
              'Could not connect to AI services. Make sure Bun server and Chatbot.py are running.',
          responseTimeSec: 0,
          source: ChatbotSource.error,
        );
      }
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

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'New AI failed');
    }

    return _formatNewAiResponse(data);
  }

  Future<ChatbotResponse> _askOldFlask(String question) async {
    final response = await http
        .post(
          Uri.parse('$_oldFlaskBaseUrl/chat'),
          headers: const {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'question': question,
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      throw Exception('Old chatbot server error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    return ChatbotResponse(
      answer: (data['answer'] ?? 'No answer found.').toString(),
      responseTimeSec: ((data['response_time_sec'] ?? 0) as num).toDouble(),
      source: ChatbotSource.oldFlaskFallback,
    );
  }

  String _formatNewAiResponse(Map<String, dynamic> data) {
    final title = data['title']?.toString() ?? '';
    final location = data['location']?.toString() ?? '';
    final content = data['content']?.toString() ?? '';
    final historicalFacts = List<String>.from(data['historical_facts'] ?? []);
    final travelTips = List<String>.from(data['travel_tips'] ?? []);

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

    return buffer.toString().trim();
  }

  double _elapsedSeconds(DateTime start) {
    return DateTime.now().difference(start).inMilliseconds / 1000.0;
  }
}

enum ChatbotSource {
  none,
  newAi,
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