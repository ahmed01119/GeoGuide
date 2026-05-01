import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

class SavedAiImage {
  final String id;
  final String imageBase64;
  final String title;
  final String location;
  final String content;
  final List<String> historicalFacts;
  final List<String> travelTips;
  final String category;
  final List<String> tags;
  final DateTime? savedAt;

  const SavedAiImage({
    required this.id,
    required this.imageBase64,
    required this.title,
    required this.location,
    required this.content,
    required this.historicalFacts,
    required this.travelTips,
    required this.category,
    required this.tags,
    required this.savedAt,
  });

  Uint8List get imageBytes => base64Decode(imageBase64);

  factory SavedAiImage.fromJson(Map<String, dynamic> json, String id) {
    DateTime? parseSavedAt(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return SavedAiImage(
      id: id,
      imageBase64: (json['imageBase64'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      historicalFacts: List<String>.from(json['historicalFacts'] ?? const []),
      travelTips: List<String>.from(json['travelTips'] ?? const []),
      category: (json['category'] ?? '').toString(),
      tags: List<String>.from(json['tags'] ?? const []),
      savedAt: parseSavedAt(json['savedAt']),
    );
  }
}
