// ============================================================
//  utils/city_seeder.dart
//
//  Run this ONCE to seed Egypt's major cities into Firestore.
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoguide/constants/constants.dart';

class CitySeeder {
  CitySeeder._();

  static Future<void> seedIfEmpty() async {
    final db = FirebaseFirestore.instance;
    final snap = await db.collection('cities').limit(1).get();

    if (snap.docs.isNotEmpty) {
      print('[Seeder] Cities already seeded.');
      return;
    }

    print('[Seeder] Seeding Egypt cities...');

    final batch = db.batch();

    for (final city in AppConstants.egyptCities) {
      final ref = db.collection('cities').doc();
      batch.set(ref, {
        'name': (city['name'] ?? '').toString().trim(),
        'lat': ((city['lat'] ?? 0) as num).toDouble(),
        'lng': ((city['lng'] ?? 0) as num).toDouble(),
        'image': '',
      });
    }

    await batch.commit();
    print('[Seeder] Done!');
  }
}