import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class AiImageDetails {
  final String title;
  final String location;
  final String content;
  final List<String> historicalFacts;
  final List<String> travelTips;
  final String category;
  final List<String> tags;

  AiImageDetails({
    required this.title,
    required this.location,
    required this.content,
    required this.historicalFacts,
    required this.travelTips,
    required this.category,
    required this.tags,
  });

  factory AiImageDetails.fromJson(Map<String, dynamic> json) {
    final metadataRaw = json['metadata'];
    final metadata =
        metadataRaw is Map<String, dynamic> ? metadataRaw : <String, dynamic>{};

    return AiImageDetails(
      title: (json['title'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      historicalFacts: (json['historical_facts'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      travelTips: (json['travel_tips'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      category: (metadata['category'] ?? '').toString(),
      tags: (metadata['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

class LandmarkImageAiService {
  static const String baseUrl =
      'https://geoguide-organization-geoguide-api.hf.space';

  Future<AiImageDetails> describeImage(XFile imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/describe'),
          headers: const {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'image': base64Image,
            'mimeType': imageFile.mimeType ?? 'image/jpeg',
          }),
        )
        .timeout(const Duration(seconds: 120));

    Map<String, dynamic> data = {};

    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
        'Image AI returned non-JSON response: ${response.statusCode}',
      );
    }

    if (response.statusCode == 200) {
      return AiImageDetails.fromJson(data);
    }

    throw Exception(
      data['error'] ?? 'Failed to describe image: ${response.statusCode}',
    );
  }
}