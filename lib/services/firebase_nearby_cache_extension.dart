// ============================================================
//  services/firebase_nearby_cache_extension.dart
//
//  Adds persistent nearbyPlaces caching to FirebaseService without
//  changing the private fields inside firebase_service.dart.
//
//  Usage:
//  1) Put this file at:
//     lib/services/firebase_nearby_cache_extension.dart
//
//  2) In place-info.dart add:
//     import 'package:geoguide/services/firebase_nearby_cache_extension.dart';
//
//  Then widget.firebase.saveNearbyPlacesForLandmark(...) will be available.
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoguide/services/firebase_service.dart';

extension FirebaseNearbyCacheExtension on FirebaseService {
  Future<void> saveNearbyPlacesForLandmark({
    required String placeId,
    required List<Map<String, dynamic>> nearbyPlaces,
  }) async {
    final id = placeId.trim();
    if (id.isEmpty || nearbyPlaces.isEmpty) return;

    final cleaned = _cleanNearbyPlaces(nearbyPlaces);
    if (cleaned.isEmpty) return;

    await FirebaseFirestore.instance.collection('landmarks').doc(id).set({
      'nearbyPlaces': cleaned,
      'nearbyUpdatedAt': FieldValue.serverTimestamp(),
      'nearbyUpdatedAtClient': DateTime.now().toIso8601String(),
      'nearbyRefreshedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  List<Map<String, dynamic>> _cleanNearbyPlaces(
    List<Map<String, dynamic>> raw,
  ) {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final item in raw) {
      final name = (item['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final category = _normalizeCategory(
        (item['category'] ?? 'tourist').toString(),
      );

      final key = '${_normalizeText(name)}|$category';
      if (!seen.add(key)) continue;

      result.add({
        'placeId': (item['placeId'] ?? '').toString(),
        'name': name,
        'category': category,
        'address': (item['address'] ?? '').toString(),
        'lat': _toDouble(item['lat']),
        'lng': _toDouble(item['lng']),
        'distanceKm': _toDouble(item['distanceKm']),
        'rating': _toDouble(item['rating']),
        'userRatingsTotal': _toInt(item['userRatingsTotal']),
        'priceLevel': (item['priceLevel'] ?? '').toString(),
        'isOpenNow': item['isOpenNow'] == true,
        'hasOpeningHours': item['hasOpeningHours'] == true,
        'imageUrl': (item['imageUrl'] ?? '').toString(),
        'types': _toStringList(item['types']),
        'mapsUrl': (item['mapsUrl'] ?? '').toString(),
        'bookingUrl': item['bookingUrl']?.toString(),
        'wikipediaUrl': item['wikipediaUrl']?.toString(),
        'phone': item['phone']?.toString(),
        'website': item['website']?.toString(),
        'fetchedAt': (item['fetchedAt'] ?? DateTime.now().toIso8601String())
            .toString(),
      });

      if (result.length >= 90) break;
    }

    return result;
  }

  String _normalizeCategory(String raw) {
    final cat = raw.trim().toLowerCase();

    if (cat.contains('hotel') ||
        cat.contains('hostel') ||
        cat.contains('resort') ||
        cat.contains('guest') ||
        cat.contains('motel') ||
        cat.contains('apartment')) {
      return 'hotel';
    }

    if (cat.contains('restaurant') ||
        cat.contains('food') ||
        cat.contains('مطعم')) {
      return 'restaurant';
    }

    if (cat.contains('cafe') ||
        cat.contains('coffee') ||
        cat.contains('bakery') ||
        cat.contains('pastry') ||
        cat.contains('dessert') ||
        cat.contains('مقهى') ||
        cat.contains('كافيه')) {
      return 'cafe';
    }

    if (cat.contains('outing') ||
        cat.contains('park') ||
        cat.contains('garden') ||
        cat.contains('mall') ||
        cat.contains('cinema') ||
        cat.contains('theatre') ||
        cat.contains('zoo') ||
        cat.contains('aquarium') ||
        cat.contains('theme') ||
        cat.contains('leisure') ||
        cat.contains('حديقة') ||
        cat.contains('مول') ||
        cat.contains('سينما') ||
        cat.contains('خروجات')) {
      return 'outing';
    }

    return 'tourist';
  }

  String _normalizeText(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[\u064B-\u065F]'), '')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '0').toString()) ?? 0;
  }

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '0').toString()) ?? 0;
  }

  List<String> _toStringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }
}
