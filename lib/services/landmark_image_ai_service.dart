import 'dart:convert';

import 'package:flutter/foundation.dart';
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
    final metadata = json['metadata'] ?? {};

    return AiImageDetails(
      title: json['title'] ?? '',
      location: json['location'] ?? '',
      content: json['content'] ?? '',
      historicalFacts: List<String>.from(json['historical_facts'] ?? []),
      travelTips: List<String>.from(json['travel_tips'] ?? []),
      category: metadata['category'] ?? '',
      tags: List<String>.from(metadata['tags'] ?? []),
    );
  }
}

class LandmarkImageAiService {
  //   static const String laptopIp = '192.168.1.6'; // غيريه لـ IP جهازك

  // static String get baseUrl {
  //   if (kIsWeb) {
  //     return 'http://localhost:3000';
  //   }

  //   // Android Emulator
  //   return 'http://10.0.2.2:3000';

  //   // Real Android/iPhone device
  //   //return 'http://$laptopIp:3000';
  // }
static const String baseUrl =
    "https://mostafa1249687-geoguide-api.hf.space";
  Future<AiImageDetails> describeImage(XFile imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final response = await http.post(
      Uri.parse('$baseUrl/api/describe'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'image': base64Image,
        'mimeType': imageFile.mimeType ?? 'image/jpeg',
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return AiImageDetails.fromJson(data);
    } else {
      throw Exception(data['error'] ?? 'Failed to describe image');
    }
  }
}