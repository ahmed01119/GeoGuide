// ============================================================
//  canonical_city_resolver.dart
//
//  Single canonicalization path for Egyptian city names + ids.
//  Used by persistence, search city hints, and home/city UI context.
//  No per-landmark "this POI belongs to city X" tables — only aliases
//  for regional / spelling variants mapping to one canonical label, then
//  matching to Firestore `cities` documents by id/name.
// ============================================================

import 'dart:math' as math;

import 'package:geoguide/models.dart/createCity_model.dart';
import 'package:geoguide/models.dart/landmark_model.dart';

/// Result of resolving free text + optional UI city id to one city row.
class CanonicalCityResolution {
  /// Firestore `cities` document id when matched; empty if unknown until create.
  final String canonicalCityId;

  /// Canonical display name (matches `City.name` in Firestore when matched).
  final String canonicalCityName;

  /// Alias keys from the table that participated in the match.
  final List<String> aliasesMatched;

  /// 1.0 = preferredCityId matched; ~0.9 = strong name match; lower = inferred only.
  final double confidence;

  const CanonicalCityResolution({
    required this.canonicalCityId,
    required this.canonicalCityName,
    required this.aliasesMatched,
    required this.confidence,
  });
}

class CanonicalCityResolver {
  CanonicalCityResolver._();

  /// Longest keys first so e.g. "marsa matrouh" wins over "matrouh".
  static final List<MapEntry<String, String>> _sortedAliasEntries =
      _buildSortedAliasEntries();

  static List<MapEntry<String, String>> _buildSortedAliasEntries() {
    const raw = <String, String>{
      // Cairo / Giza
      'cairo': 'Cairo',
      'القاهرة': 'Cairo',
      'القاهره': 'Cairo',
      'cairo governorate': 'Cairo',
      'giza': 'Giza',
      'giza governorate': 'Giza',
      'giza plateau': 'Giza',
      'الجيزة': 'Giza',
      'الجيزه': 'Giza',
      'haram': 'Giza',
      'al haram': 'Giza',
      'el haram': 'Giza',
      'nazlet el semman': 'Giza',
      'nazlet al samman': 'Giza',
      // Luxor
      'luxor': 'Luxor',
      'luxor city': 'Luxor',
      'luxor governorate': 'Luxor',
      'الأقصر': 'Luxor',
      'الاقصر': 'Luxor',
      'al uqsur': 'Luxor',
      'karnak': 'Luxor',
      'old karnak': 'Luxor',
      'الكرنك': 'Luxor',
      // Aswan
      'aswan': 'Aswan',
      'أسوان': 'Aswan',
      'اسوان': 'Aswan',
      'aswan governorate': 'Aswan',
      'abu simbel': 'Aswan',
      'abu simbel city': 'Aswan',
      // Alexandria
      'alexandria': 'Alexandria',
      'alex': 'Alexandria',
      'الإسكندرية': 'Alexandria',
      'الاسكندرية': 'Alexandria',
      'alexandria governorate': 'Alexandria',
      // Red Sea — El Gouna is grouped under Hurghada hub for app city lists
      'hurghada': 'Hurghada',
      'hurgada': 'Hurghada',
      'الغردقة': 'Hurghada',
      'غردقة': 'Hurghada',
      'al ghardaqah': 'Hurghada',
      'el gouna': 'Hurghada',
      'gouna': 'Hurghada',
      'الجونة': 'Hurghada',
      'red sea': 'Hurghada',
      'red sea governorate': 'Hurghada',
      'south red sea': 'Hurghada',
      // Sinai
      'sharm el sheikh': 'Sharm El Sheikh',
      'sharm el-sheikh': 'Sharm El Sheikh',
      'sharm': 'Sharm El Sheikh',
      'شرم الشيخ': 'Sharm El Sheikh',
      'dahab': 'Dahab',
      'دهب': 'Dahab',
      'south sinai': 'Sharm El Sheikh',
      'south sinai governorate': 'Sharm El Sheikh',
      // Matrouh governorate — never Siwa
      'matrouh': 'Matrouh',
      'marsa matrouh': 'Matrouh',
      'marsa matruh': 'Matrouh',
      'matruh': 'Matrouh',
      'مرسى مطروح': 'Matrouh',
      'مطروح': 'Matrouh',
      'matrouh governorate': 'Matrouh',
      // Other
      'siwa': 'Siwa',
      'siwa oasis': 'Siwa',
      'سيوة': 'Siwa',
      'port said': 'Port Said',
      'بورسعيد': 'Port Said',
      'suez': 'Suez',
      'السويس': 'Suez',
      'ismailia': 'Ismailia',
      'الإسماعيلية': 'Ismailia',
      'faiyum': 'Faiyum',
      'fayoum': 'Faiyum',
      'الفيوم': 'Faiyum',
      'minya': 'Minya',
      'المنيا': 'Minya',
      'sohag': 'Sohag',
      'سوهاج': 'Sohag',
      'qena': 'Qena',
      'قنا': 'Qena',
    };

    final entries = raw.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    return entries;
  }

  static String _normBlob(String value) {
    return value
        .toLowerCase()
        .replaceAll('governorate', '')
        .replaceAll('egypt', '')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Public: normalize user/query text the same way alias hits are evaluated.
  static String normalizeCityBlob(String raw) => _normBlob(raw);

  /// After [PlaceSearchPipeline]-style normalization (digits, hamza, etc.).
  static String? cityNameFromNormalizedSearchKey(String normalizedKey) {
    final n = normalizedKey.trim();
    if (n.isEmpty) return null;
    for (final e in _sortedAliasEntries) {
      final key = _normBlob(e.key);
      if (key.isEmpty) continue;
      if (n.contains(key)) return e.value;
    }
    return null;
  }

  static String? _canonicalNameFromBlob(String blob) {
    final n = _normBlob(blob);
    if (n.isEmpty) return null;
    final matched = <String>[];
    for (final e in _sortedAliasEntries) {
      final key = _normBlob(e.key);
      if (key.isEmpty) continue;
      if (n.contains(key)) {
        matched.add(e.key);
        return e.value;
      }
    }
    return null;
  }

  static bool namesAlign(String a, String b) {
    final x = _normBlob(a);
    final y = _normBlob(b);
    if (x.isEmpty || y.isEmpty) return false;
    if (x == y) return true;
    if (x.contains(y) || y.contains(x)) return true;
    return false;
  }

  static City? _cityById(List<City> cities, String id) {
    final t = id.trim();
    if (t.isEmpty) return null;
    for (final c in cities) {
      if (c.id == t) return c;
    }
    return null;
  }

  static City? _matchKnownCityByName(List<City> cities, String canonicalName) {
    final target = _normBlob(canonicalName);
    if (target.isEmpty) return null;

    City? best;
    var bestScore = 0;
    for (final c in cities) {
      final cn = _normBlob(c.name);
      if (cn.isEmpty) continue;
      var score = 0;
      if (cn == target) {
        score = 100;
      } else if (cn.contains(target) || target.contains(cn)) {
        score = 80 - (cn.length - target.length).abs();
      } else if (_tokenOverlap(cn, target) >= 0.55) {
        score = 50;
      }
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return bestScore >= 50 ? best : null;
  }

  static double _tokenOverlap(String a, String b) {
    final ta = a.split(' ').where((e) => e.length > 2).toSet();
    final tb = b.split(' ').where((e) => e.length > 2).toSet();
    if (ta.isEmpty || tb.isEmpty) return 0;
    final inter = ta.intersection(tb).length;
    return inter / math.max(ta.length, tb.length);
  }

  /// Main entry: unify city id + display name used across search, save, and UI.
  static CanonicalCityResolution resolveCanonicalCity({
    required List<City> knownCities,
    String? query,
    String? address,
    String? cityName,
    String? preferredCityId,
    double? lat,
    double? lng,
  }) {
    final blob = [
      query,
      address,
      cityName,
    ].map((e) => (e ?? '').trim()).where((e) => e.isNotEmpty).join(' ');

    final fromAliases = _canonicalNameFromBlob(blob);
    final matchedAliases = <String>[];

    if (fromAliases != null) {
      final n = _normBlob(blob);
      for (final e in _sortedAliasEntries) {
        final key = _normBlob(e.key);
        if (key.isNotEmpty && n.contains(key)) matchedAliases.add(e.key);
      }
    }

    final prefId = (preferredCityId ?? '').trim();
    if (prefId.isNotEmpty) {
      final prefCity = _cityById(knownCities, prefId);
      if (prefCity != null) {
        if (fromAliases == null || namesAlign(fromAliases, prefCity.name)) {
          return CanonicalCityResolution(
            canonicalCityId: prefCity.id,
            canonicalCityName: prefCity.name,
            aliasesMatched: matchedAliases,
            confidence: 1.0,
          );
        }
        // UI city id wins for persistence consistency; text hint may disagree.
        return CanonicalCityResolution(
          canonicalCityId: prefCity.id,
          canonicalCityName: prefCity.name,
          aliasesMatched: [...matchedAliases, 'preferredCityId'],
          confidence: 0.92,
        );
      }
    }

    final canon = fromAliases ?? (cityName?.trim().isNotEmpty == true ? cityName!.trim() : '');

    if (canon.isEmpty || _normBlob(canon).isEmpty) {
      return CanonicalCityResolution(
        canonicalCityId: '',
        canonicalCityName: '',
        aliasesMatched: matchedAliases,
        confidence: 0,
      );
    }

    final hit = _matchKnownCityByName(knownCities, canon);
    if (hit != null) {
      return CanonicalCityResolution(
        canonicalCityId: hit.id,
        canonicalCityName: hit.name,
        aliasesMatched: matchedAliases,
        confidence: fromAliases != null ? 0.9 : 0.75,
      );
    }

    return CanonicalCityResolution(
      canonicalCityId: '',
      canonicalCityName: canon,
      aliasesMatched: matchedAliases,
      confidence: fromAliases != null ? 0.55 : 0.35,
    );
  }

  /// Convenience for Firestore saves from a [Landmark].
  static CanonicalCityResolution resolveForLandmark(
    Landmark lm,
    List<City> knownCities,
  ) {
    return resolveCanonicalCity(
      knownCities: knownCities,
      query: '${lm.name} ${lm.shortDescription}',
      address: lm.address,
      cityName: lm.city,
      preferredCityId: lm.cityId.trim().isNotEmpty ? lm.cityId : null,
      lat: lm.lat,
      lng: lm.lng,
    );
  }
}
