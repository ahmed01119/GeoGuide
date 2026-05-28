// ============================================================
//  services/firebase_service.dart (REPAIRED)
//
//  NOTE:
//  This file is a temporary repair target.
//  It is NOT wired into the app by default.
//  Use it only to validate the correct structure for
//  FirebaseService + AdminHardDeletePlaceSummary.
// ============================================================


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/place_category_normalizer.dart';
import '../core/place_search_pipeline.dart';
import '../models.dart/createCity_model.dart';
import '../models.dart/landmark_model.dart';
import 'image-service.dart';

/// Debug / post-save check: would this landmark appear on the city page list?
class LandmarkCityVisibilityCheck {
  final bool visible;
  final String reason;
  final String cityId;
  const LandmarkCityVisibilityCheck({
    required this.visible,
    required this.reason,
    this.cityId = '',
  });
}

class FirebaseService {
  final FirebaseFirestore _db;

  FirebaseService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  ImageService? _imageValidator;
  ImageService get _imageValidatorNonNull => _imageValidator ??= ImageService();

  Future<bool> imageOwnersAllowHeroSharingWithSubject(Landmark subject, List<String> ownerIds) =>
      _allImageOwnersCompatibleWithSubject(subject, ownerIds);

  Future<bool> _allImageOwnersCompatibleWithSubject(Landmark subject, List<String> ownerIds) async {
    final self = subject.id.trim();
    for (final oid in ownerIds) {
      final o = oid.trim();
      if (o.isEmpty) continue;
      if (self.isNotEmpty && o == self) continue;
      final other = await getLandmarkById(o);
      if (other == null) continue;
      if (!PlaceSearchPipeline.isSameLogicalPlaceForImageSharing(subject, other)) {
        return false;
      }
    }
    return true;
  }

  Future<LandmarkCityVisibilityCheck> verifyLandmarkVisibleInCity(String landmarkId) async {
    final id = landmarkId.trim();
    if (id.isEmpty) {
      return const LandmarkCityVisibilityCheck(visible: false, reason: 'missing_id');
    }
    final lm = await getLandmarkById(id);
    if (lm == null) {
      return const LandmarkCityVisibilityCheck(visible: false, reason: 'missing_document');
    }

    final cid = lm.cityId.trim();
    if (lm.hidden) {
      return LandmarkCityVisibilityCheck(visible: false, reason: 'hidden=true', cityId: cid);
    }
    if (lm.invalidPlace) {
      return LandmarkCityVisibilityCheck(visible: false, reason: 'invalidPlace=true', cityId: cid);
    }
    if (lm.isDuplicate) {
      return LandmarkCityVisibilityCheck(visible: false, reason: 'isDuplicate=true', cityId: cid);
    }
    if (cid.isEmpty) {
      return const LandmarkCityVisibilityCheck(visible: false, reason: 'cityId_empty');
    }

    try {
      final list = await getLandmarksByCity(cid);
      final found = list.any((e) => e.id == lm.id);
      if (!found) {
        return LandmarkCityVisibilityCheck(visible: false, reason: 'not_in_getLandmarksByCity_results', cityId: cid);
      }
    } catch (e) {
      return LandmarkCityVisibilityCheck(visible: false, reason: 'city_query_error:$e', cityId: cid);
    }

    return LandmarkCityVisibilityCheck(visible: true, reason: 'ok', cityId: cid);
  }

  Landmark _coalesceAdminLandmarkCityAndCategory(Landmark lm, List<City> cities) {
    var out = lm;
    final cid = lm.cityId.trim();
    if (cid.isNotEmpty) {
      for (final c in cities) {
        if (c.id == cid) {
          out = out.copyWith(cityId: c.id, city: c.name);
          break;
        }
      }
    }
    final cat = PlaceCategoryNormalizer.normalize(out.category, contextText: out.name);
    return out.copyWith(category: cat);
  }

  Future<Landmark> _stripInvalidIncomingImages(Landmark lm) async {
    final hero = lm.imageUrl.trim();
    if (hero.isEmpty) return lm;

    final owners = await findLandmarkIdsWithImageUrl(hero);
    final ownersOk = await _allImageOwnersCompatibleWithSubject(lm, owners);

    final ok = ownersOk &&
        _imageValidatorNonNull.validateImageCandidateForPlace(
          url: hero,
          metaText: '${lm.name} ${lm.city} ${lm.category} $hero',
          placeName: lm.name,
          cityName: lm.city,
          category: lm.category,
        );

    if (ok) return lm;

    if (kDebugMode) {
      debugPrint('[Firebase] strip invalid/duplicate hero on save: ${lm.name}');
    }

    final filteredMedia = lm.mediaUrls.where((u) => u.trim() != hero).toList();
    return lm.copyWith(
      imageUrl: '',
      mediaUrls: filteredMedia,
      imageRejectedAt: DateTime.now(),
      imageRejectedReason: 'invalid_or_duplicate_hero_on_save',
      imageNeedsReview: true,
    );
  }

  String? get currentUserId => _auth.currentUser?.uid;
  String get currentUserEmail => _auth.currentUser?.email ?? '';

  Future<Map<String, dynamic>?> _currentUserDoc() async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) return null;
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  Future<bool> isCurrentUserAdmin() async {
    final data = await _currentUserDoc();
    final role = (data?['role'] ?? '').toString().trim().toLowerCase();
    return role == 'admin';
  }

  Future<bool> isCurrentUserBlocked() async {
    final data = await _currentUserDoc();
    return (data?['isBlocked'] ?? false).toString().toLowerCase() == 'true';
  }

  Future<void> requireAdmin() async {
    final ok = await isCurrentUserAdmin();
    if (!ok) throw Exception('Admin access required.');
  }

  Future<void> addAdminLog({
    required String actionType,
    required String targetCollection,
    required String targetId,
    String reason = '',
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) async {
    final uid = currentUserId;
    if (uid == null || uid.isEmpty) return;
    await _db.collection('admin_logs').add({
      'actionType': actionType.trim(),
      'adminUid': uid,
      'adminEmail': currentUserEmail,
      'targetCollection': targetCollection.trim(),
      'targetId': targetId.trim(),
      'reason': reason.trim(),
      if (before != null) 'before': before,
      if (after != null) 'after': after,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  // IMPORTANT: keep adminHardDeletePlaceWithCascade INSIDE FirebaseService.
  Future<AdminHardDeletePlaceSummary> adminHardDeletePlaceWithCascade({
    required String placeId,
    required String typedConfirmation,
  }) async {
    await requireAdmin();

    final id = placeId.trim();
    if (id.isEmpty) {
      return const AdminHardDeletePlaceSummary(deletedLandmark: '');
    }

    final nowIso = DateTime.now().toIso8601String();

    final failedSteps = <String>[];
    var favoritesDeleted = 0;
    var reviewsDeleted = 0;
    var nearbyDeleted = 0;
    var duplicateRefsUpdated = 0;

    String targetName = '';
    try {
      final lm = await getLandmarkById(id);
      targetName = lm?.name ?? '';
    } catch (_) {}

    final beforeSummary = <String, dynamic>{
      'targetId': id,
      if (targetName.isNotEmpty) 'targetName': targetName,
      'typedConfirmation': typedConfirmation.trim(),
      'before': const {'note': 'summary only'},
    };

    bool landmarkDeleted = false;

    Future<void> safeStep(String stepName, Future<void> Function() fn) async {
      try {
        await fn();
      } catch (e) {
        failedSteps.add('$stepName:$e');
      }
    }

    await safeStep('delete_landmark_doc', () async {
      await _db.collection('landmarks').doc(id).delete();
      landmarkDeleted = true;
    });

    await safeStep('favorites_cleanup', () async {
      final usersSnap = await _db.collection('users').get();
      for (final u in usersSnap.docs) {
        final uid = u.id;
        try {
          final ref = _db.collection('users').doc(uid).collection('favorites').doc(id);
          final doc = await ref.get();
          if (doc.exists) {
            await ref.delete();
            favoritesDeleted++;
          }
        } catch (e) {
          failedSteps.add('favorites_cleanup:user=$uid:$e');
        }
      }
    });

    await safeStep('reviews_cleanup', () async {
      final reviewsSnap = await _db.collection('landmarks').doc(id).collection('reviews').get();
      for (final r in reviewsSnap.docs) {
        await r.reference.delete();
        reviewsDeleted++;
      }
    });

    await safeStep('nearby_cleanup', () async {
      final lmRef = _db.collection('landmarks').doc(id);

      try {
        final doc = await lmRef.get();
        if (doc.exists) {
          final data = doc.data();
          final nearbyList = data?['nearbyPlaces'];
          if (nearbyList is List) {
            nearbyDeleted += nearbyList.length;
          }
          await lmRef.update({'nearbyPlaces': const []});
        }
      } catch (_) {}

      try {
        final bSnap = await lmRef.collection('bookingLinks').get();
        for (final b in bSnap.docs) {
          await b.reference.delete();
          nearbyDeleted++;
        }
      } catch (_) {}
    });

    await safeStep('duplicate_refs_update', () async {
      final dupSnap = await _db.collection('landmarks').where('duplicateOf', isEqualTo: id).get();
      for (final d in dupSnap.docs) {
        await d.reference.set({'duplicateOf': ''}, SetOptions(merge: true));
        duplicateRefsUpdated++;
      }
    });

    final status = failedSteps.isEmpty
        ? 'success'
        : landmarkDeleted
            ? 'partial'
            : 'failure';

    try {
      await _db.collection('admin_logs').add({
        'actionType': 'place_deleted',
        'status': status,
        'adminUid': currentUserId ?? '',
        'adminEmail': currentUserEmail,
        'targetCollection': 'landmarks',
        'targetId': id,
        if (targetName.isNotEmpty) 'targetName': targetName,
        'reason': 'adminHardDelete',
        'origin': typedConfirmation.trim(),
        if (beforeSummary.isNotEmpty) 'beforeSummary': beforeSummary,
        'afterSummary': {
          'deletedLandmark': id,
          'favoritesDeleted': favoritesDeleted,
          'reviewsDeleted': reviewsDeleted,
          'nearbyDeleted': nearbyDeleted,
          'duplicateRefsUpdated': duplicateRefsUpdated,
        },
        if (failedSteps.isNotEmpty) 'errorMessage': failedSteps.first,
        'createdAt': nowIso,
      });
    } catch (_) {}

    return AdminHardDeletePlaceSummary(
      deletedLandmark: id,
      favoritesDeleted: favoritesDeleted,
      reviewsDeleted: reviewsDeleted,
      nearbyDeleted: nearbyDeleted,
      duplicateRefsUpdated: duplicateRefsUpdated,
      failedSteps: failedSteps,
    );
  }

  // --- Stub methods required by this repaired file only ---
  // (The real app uses lib/services/firebase_service.dart)
  Future<Landmark?> getLandmarkById(String placeId) async => null;
  Future<List<Landmark>> getLandmarksByCity(String cityId) async => const [];
  Future<List<String>> findLandmarkIdsWithImageUrl(String imageUrl) async => const [];
}

class AdminHardDeletePlaceSummary {
  final String deletedLandmark;
  final int favoritesDeleted;
  final int reviewsDeleted;
  final int nearbyDeleted;
  final int duplicateRefsUpdated;
  final List<String> failedSteps;

  const AdminHardDeletePlaceSummary({
    required this.deletedLandmark,
    this.favoritesDeleted = 0,
    this.reviewsDeleted = 0,
    this.nearbyDeleted = 0,
    this.duplicateRefsUpdated = 0,
    this.failedSteps = const [],
  });

  bool get isSuccess => failedSteps.isEmpty;

  Map<String, dynamic> toJson() => {
        'deletedLandmark': deletedLandmark,
        'favoritesDeleted': favoritesDeleted,
        'reviewsDeleted': reviewsDeleted,
        'nearbyDeleted': nearbyDeleted,
        'duplicateRefsUpdated': duplicateRefsUpdated,
        'failedSteps': failedSteps,
        'status': isSuccess ? 'success' : 'partial',
      };
}

