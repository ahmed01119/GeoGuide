// ============================================================
//  services/firebase_service.dart (RESTORED)
// ============================================================

// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/canonical_city_resolver.dart';
import '../core/place_category_normalizer.dart';
import '../core/place_search_pipeline.dart';
import '../models.dart/createCity_model.dart';
import '../models.dart/landmark_model.dart';
import '../models.dart/saved_ai_image_model.dart';
import 'image-service.dart';
import 'landmark_image_ai_service.dart';

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
  
  /// Reads the raw landmark document metadata to detect whether an
  /// admin/editor has modified this landmark.
  ///
  /// NOTE: This intentionally does NOT rely on the Landmark model fields,
  /// because those may be missing/stale in some code paths.
  Future<bool> isLandmarkAdminEdited(String landmarkId) async {
    final id = landmarkId.trim();
    if (id.isEmpty) return false;

    try {
      final doc = await _db.collection('landmarks').doc(id).get();
      final data = doc.data();
      if (data == null) return false;

      final sourcesRaw = data['sources'];
      final sources = sourcesRaw is Map
          ? Map<String, dynamic>.from(sourcesRaw)
          : <String, dynamic>{};

      bool hasText(dynamic value) {
        return value != null && value.toString().trim().isNotEmpty;
      }

      return hasText(data['lastAdminEditAt']) ||
          hasText(data['lastAdminEditBy']) ||
          hasText(data['lastAdminEditByEmail']) ||
          data['createdByAdmin'] == true ||
          data['adminVerified'] == true ||
          data['isVerified'] == true ||
          hasText(sources['lastAdminEditAt']);
    } catch (e) {
      debugPrint('[AdminEditedCheckError] id=$id error=$e');
      return false;
    }
  }

  final FirebaseFirestore _db;

  FirebaseService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  ImageService? _imageValidator;
  ImageService get _imageValidatorNonNull => _imageValidator ??= ImageService();

  Future<bool> imageOwnersAllowHeroSharingWithSubject(
    Landmark subject,
    List<String> ownerIds,
  ) =>
      _allImageOwnersCompatibleWithSubject(subject, ownerIds);

  Future<bool> _allImageOwnersCompatibleWithSubject(
    Landmark subject,
    List<String> ownerIds,
  ) async {
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

  Future<LandmarkCityVisibilityCheck> verifyLandmarkVisibleInCity(
    String landmarkId,
  ) async {
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
        return LandmarkCityVisibilityCheck(
          visible: false,
          reason: 'not_in_getLandmarksByCity_results',
          cityId: cid,
        );
      }
    } catch (e) {
      return LandmarkCityVisibilityCheck(
        visible: false,
        reason: 'city_query_error:$e',
        cityId: cid,
      );
    }

    return LandmarkCityVisibilityCheck(visible: true, reason: 'ok', cityId: cid);
  }

  Landmark _coalesceAdminLandmarkCityAndCategory(
    Landmark lm,
    List<City> cities,
  ) {
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

  // NOTE: The original repository's _buildMergeMap admin-protection logic is
  // intentionally kept inside the function body to avoid Dart syntax issues.


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

  // ──────────────────────────────────────────────────────────────
  //  PARTIAL UPDATE  (used by PlaceRepository)
  // ──────────────────────────────────────────────────────────────
  Future<void> partialUpdate(String docId, Map<String, dynamic> fields) async {
    if (docId.trim().isEmpty || fields.isEmpty) return;

    if (kDebugMode) {
      debugPrint('[PartialUpdate] doc=$docId fields=${fields.keys.toList()}');
    }

    // Safety guard: do not overwrite admin-edited images during automatic enrichment.
    // Only allow imageUrl/mediaUrls replacement when the caller explicitly marks
    // the operation as admin-triggered.
    final wantsImageWrite =
        fields.containsKey('imageUrl') || fields.containsKey('mediaUrls');

    final callerSource = (fields['imageUpdateSource'] ?? '').toString().trim();
    final explicitAdminImageOverwrite = callerSource == 'admin_image_refresh';

    if (wantsImageWrite && !explicitAdminImageOverwrite) {
      final snap = await _db.collection('landmarks').doc(docId).get();
      if (snap.exists && snap.data() != null) {
        final data = snap.data()!;

        final lastAdminEditAt = (data['lastAdminEditAt'] ?? '').toString().trim();
        final createdByAdmin = (data['createdByAdmin'] ?? false)
            .toString()
            .trim()
            .toLowerCase() == 'true';
        final adminVerified = (data['adminVerified'] ?? data['isVerified'] ?? false)
            .toString()
            .trim()
            .toLowerCase() == 'true';
        final isVerified = (data['isVerified'] ?? false)
            .toString()
            .trim()
            .toLowerCase() == 'true';
        final lastAdminEditBy = (data['lastAdminEditBy'] ?? '').toString().trim();
        final lastAdminEditByEmail =
            (data['lastAdminEditByEmail'] ?? '').toString().trim();

        final sources = (data['sources'] is Map)
            ? Map<String, dynamic>.from(data['sources'] as Map)
            : const <String, dynamic>{};
        final sourcesLastAdminEditAt =
            (sources['lastAdminEditAt'] ?? '').toString().trim();

        final isAdminEdited = lastAdminEditAt.isNotEmpty ||
            sourcesLastAdminEditAt.isNotEmpty ||
            createdByAdmin ||
            adminVerified ||
            isVerified ||
            lastAdminEditBy.isNotEmpty ||
            lastAdminEditByEmail.isNotEmpty;

        if (isAdminEdited) {
          if (kDebugMode) {
            debugPrint(
              '[ImageEnrichSkipAdminImage] doc=$docId reason=admin_edited_auto_enrichment imageUpdateSource=$callerSource fields=${fields.keys.toList()}',
            );
          }

          final updatedFields = Map<String, dynamic>.from(fields);
          updatedFields.remove('imageUrl');
          updatedFields.remove('mediaUrls');
          updatedFields.remove('imagesRefreshedAt');

          // Remove enrichment-relevant timestamps for images as well.
          // Keep generic 'updatedAt' if provided.
          updatedFields.remove('imagesAreFallback');
          updatedFields.remove('imagesFailureReason');
          updatedFields.remove('imagesRejectedReason');
          updatedFields.remove('imagesFailureReason');
          updatedFields.remove('imageNeedsReview');
          updatedFields.remove('imageRejectedReason');
          updatedFields.remove('imageRejectedAt');
          updatedFields.remove('imagesFailedAt');

          // Ensure we still don't pass the internal routing param to Firestore.
          updatedFields.remove('imageUpdateSource');

          await _db
              .collection('landmarks')
              .doc(docId)
              .set(updatedFields, SetOptions(merge: true));
          return;
        }
      }
    }

    // Clean internal routing param if present.
    final cleaned = Map<String, dynamic>.from(fields);
    cleaned.remove('imageUpdateSource');

    await _db
        .collection('landmarks')
        .doc(docId)
        .set(cleaned, SetOptions(merge: true));
  }



  // ──────────────────────────────────────────────────────────────
  //  SAVED AI IMAGES
  //  Path: users/{uid}/saved_ai_images/{saveKey}
  // ──────────────────────────────────────────────────────────────

  String buildSavedAiImageKey({
    required String imageBase64,
    required AiImageDetails details,
  }) {
    final raw =
        '${imageBase64.length}|${imageBase64.substring(0, imageBase64.length > 200 ? 200 : imageBase64.length)}';

    int hash = 0;
    for (final unit in raw.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }

    return 'ai_$hash';
  }

  Future<void> saveAiImage({

    required String saveKey,
    required String imageBase64,
    required AiImageDetails details,
  }) async {
    final uid = currentUserId;
    if (uid == null || saveKey.trim().isEmpty) return;

    await _db
        .collection('users')
        .doc(uid)
        .collection('saved_ai_images')
        .doc(saveKey.trim())
        .set({
      'imageBase64': imageBase64,
      'title': details.title,
      'location': details.location,
      'content': details.content,
      'historicalFacts': details.historicalFacts,
      'travelTips': details.travelTips,
      'category': details.category,
      'tags': details.tags,
      'savedAt': FieldValue.serverTimestamp(),
      'savedAtClient': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  Future<void> removeSavedAiImage(String saveKey) async {
    final uid = currentUserId;
    if (uid == null || saveKey.trim().isEmpty) return;

    await _db
        .collection('users')
        .doc(uid)
        .collection('saved_ai_images')
        .doc(saveKey.trim())
        .delete();
  }

  Future<bool> isAiImageSaved(String saveKey) async {
    final uid = currentUserId;
    if (uid == null || saveKey.trim().isEmpty) return false;

    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('saved_ai_images')
        .doc(saveKey.trim())
        .get();

    return doc.exists;
  }

  Stream<bool> savedAiImageStream(String saveKey) {
    final uid = currentUserId;
    if (uid == null || saveKey.trim().isEmpty) return Stream.value(false);

    return _db
        .collection('users')
        .doc(uid)
        .collection('saved_ai_images')
        .doc(saveKey.trim())
        .snapshots()
        .map((doc) => doc.exists);
  }

  Stream<List<SavedAiImage>> savedAiImagesStream() {
    final uid = currentUserId;
    if (uid == null) return const Stream.empty();

    return _db
        .collection('users')
        .doc(uid)
        .collection('saved_ai_images')
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((doc) => SavedAiImage.fromJson(doc.data(), doc.id))
          .toList();
    });
  }

  // ──────────────────────────────────────────────────────────────
  //  FAVORITES
  // ──────────────────────────────────────────────────────────────
  Future<void> toggleFavorite(Landmark place) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || place.id.trim().isEmpty) return;

    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(place.id);

    final doc = await ref.get();
    if (doc.exists) {
      await ref.delete();
    } else {
      await ref.set(place.toJson(), SetOptions(merge: true));
    }
  }

  Future<bool> isFavorite(String placeId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || placeId.trim().isEmpty) return false;
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(placeId)
        .get();
    return doc.exists;
  }

  Future<List<Landmark>> getUserFavorites() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .get();
    return snap.docs.map((d) => Landmark.fromJson(d.data(), d.id)).toList();
  }

  Stream<bool> favoriteStream(String placeId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null || placeId.trim().isEmpty) return Stream.value(false);
    return _db
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(placeId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  // ──────────────────────────────────────────────────────────────
  //  PLANS
  // ──────────────────────────────────────────────────────────────
  Future<String?> savePlan({
    required List<List<Landmark>> plan,
    String? title,
    required String userId,
  }) async {
    final uid = userId.trim().isNotEmpty ? userId : _auth.currentUser?.uid;
    if (uid == null) return null;

    final formattedDays = plan.asMap().entries.map((entry) {
      return {
        'dayNumber': entry.key + 1,
        'places': entry.value
            .map((p) => {
                  'id': p.id,
                  'name': p.name,
                  'city': p.city,
                  'cityId': p.cityId,
                  'category': p.category,
                  'imageUrl': p.imageUrl,
                  'shortDescription': p.shortDescription,
                  'fullDescription': p.fullDescription,
                  'history': p.history,
                  'rating': p.rating,
                  'lat': p.lat,
                  'lng': p.lng,
                  'address': p.address,
                  'openingHours': p.openingHours,
                  'location': p.location,
                  'mediaUrls': p.mediaUrls,
                  'wikipediaUrl': p.wikipediaUrl,
                })
            .toList(),
      };
    }).toList();

    final totalPlaces = plan.fold<int>(0, (s, d) => s + d.length);
    final daysCount = plan.length;
    final allPlaces = plan.expand((e) => e).toList();
    final firstPlace = allPlaces.isNotEmpty ? allPlaces.first : null;
    final cityName = firstPlace?.city ?? 'Egypt';
    final cityId = firstPlace?.cityId ?? '';

    final ref = await _db.collection('users').doc(uid).collection('plans').add({
      'title': (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : '$cityName $daysCount-day plan',
      'daysCount': daysCount,
      'placesCount': totalPlaces,
      'city': cityName,
      'cityId': cityId,
      'days': formattedDays,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtClient': DateTime.now().toIso8601String(),
    });

    return ref.id;
  }

  Stream<List<Map<String, dynamic>>> userPlansStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _db
        .collection('users')
        .doc(uid)
        .collection('plans')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
      return snap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  Future<void> deletePlan(String planId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || planId.trim().isEmpty) return;
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('plans')
        .doc(planId.trim());
    final doc = await ref.get();
    if (!doc.exists) return;
    await ref.delete();
  }

  // ──────────────────────────────────────────────────────────────
  //  VISITED
  // ──────────────────────────────────────────────────────────────
  Future<void> toggleVisited(Landmark place) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || place.id.trim().isEmpty) return;
    final ref =
        _db.collection('users').doc(uid).collection('visited').doc(place.id);
    final doc = await ref.get();
    if (doc.exists) {
      await ref.delete();
    } else {
      await ref.set({
        ...place.toJson(),
        'visitedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Stream<bool> visitedStream(String placeId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null || placeId.trim().isEmpty) return Stream.value(false);
    return _db
        .collection('users')
        .doc(uid)
        .collection('visited')
        .doc(placeId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  // ──────────────────────────────────────────────────────────────
  //  BOOKING LINKS
  // ──────────────────────────────────────────────────────────────
  Stream<Map<String, String>> bookingLinksStream(String placeId) {
    if (placeId.trim().isEmpty) return Stream.value({});
    return _db
        .collection('landmarks')
        .doc(placeId)
        .collection('bookingLinks')
        .snapshots()
        .map((snap) {
      final result = <String, String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final title = (data['title'] as String? ?? '').trim();
        final url = (data['url'] as String? ?? '').trim();
        if (title.isNotEmpty && url.isNotEmpty) result[title] = url;
      }
      return result;
    });
  }

  // ──────────────────────────────────────────────────────────────
  //  REVIEWS & RATINGS
  // ──────────────────────────────────────────────────────────────
  Future<void> addReview({
    required String placeId,
    required double rating,
    required String comment,
  }) async {
    final uid = _auth.currentUser?.uid;
    final userName = _auth.currentUser?.displayName ?? 'User';
    if (uid == null || placeId.trim().isEmpty) return;

    await _db.collection('landmarks').doc(placeId).collection('reviews').doc(uid).set({
      'userId': uid,
      'userName': userName,
      'rating': rating,
      'comment': comment.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<Map<String, dynamic>>> reviewsStream(String placeId) {
    if (placeId.trim().isEmpty) return const Stream.empty();
    return _db
        .collection('landmarks')
        .doc(placeId)
        .collection('reviews')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  Stream<double> averageRatingStream(String placeId) {
    return reviewsStream(placeId).map((reviews) {
      if (reviews.isEmpty) return 0.0;
      double total = 0;
      for (final r in reviews) {
        total += ((r['rating'] ?? 0) as num).toDouble();
      }
      return total / reviews.length;
    });
  }

  Future<void> deleteReview({
    required String placeId,
    required String userId,
  }) async {
    if (placeId.trim().isEmpty || userId.trim().isEmpty) return;
    await _db
        .collection('landmarks')
        .doc(placeId)
        .collection('reviews')
        .doc(userId)
        .delete();
  }

  // ──────────────────────────────────────────────────────────────
  //  NEARBY SUGGESTIONS
  // ──────────────────────────────────────────────────────────────
  Stream<List<Landmark>> nearbySuggestionsStream({
    required String city,
    required String excludePlaceId,
    required double sourceLat,
    required double sourceLng,
    double maxDistanceKm = 15,
  }) {
    if (city.trim().isEmpty) return Stream.value([]);

    return _db.collection('landmarks').where('city', isEqualTo: city).snapshots().map((snap) {
      final all = snap.docs
          .map((d) => Landmark.fromJson(d.data(), d.id))
          .where((lm) => lm.id != excludePlaceId)
          .where(_isVisibleLandmark)
          .toList();

      if (sourceLat != 0 && sourceLng != 0) {
        final withDist = all.map((lm) {
          final d = _distanceKm(sourceLat, sourceLng, lm.lat, lm.lng);
          return MapEntry(lm, d);
        }).toList();

        final close = withDist
            .where((e) => e.value.isFinite && e.value <= maxDistanceKm)
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));

        if (close.isNotEmpty) {
          return close.map((e) => e.key).toList();
        }
      }

      all.sort((a, b) => b.rating.compareTo(a.rating));
      return all.take(30).toList();
    });
  }

  // ──────────────────────────────────────────────────────────────
  //  CITIES
  // ──────────────────────────────────────────────────────────────
  Future<List<City>> getCities() async {
    final snap = await _db.collection('cities').orderBy('name').get();
    return snap.docs.map((d) => City.fromJson(d.data(), d.id)).toList();
  }

  Future<String> addCity(City city) async {
    final ref = await _db.collection('cities').add(city.toJson());
    return ref.id;
  }

  Future<City?> getCityById(String id) async {
    final t = id.trim();
    if (t.isEmpty) return null;
    try {
      final doc = await _db.collection('cities').doc(t).get();
      if (!doc.exists || doc.data() == null) return null;
      return City.fromJson(doc.data()!, doc.id);
    } catch (e) {
      print('getCityById error: $e');
      return null;
    }
  }

  Future<City?> getCityByName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    final snap = await _db.collection('cities').get();
    final cities = snap.docs.map((d) => City.fromJson(d.data(), d.id)).toList();

    final resolved = CanonicalCityResolver.resolveCanonicalCity(
      knownCities: cities,
      cityName: trimmed,
    );
    if (resolved.canonicalCityId.isNotEmpty) {
      for (final c in cities) {
        if (c.id == resolved.canonicalCityId) return c;
      }
    }

    final normalized = trimmed.toLowerCase();
    for (final city in cities) {
      final cityName = city.name.trim().toLowerCase();
      if (cityName == normalized ||
          cityName.contains(normalized) ||
          normalized.contains(cityName)) {
        return city;
      }
    }
    return null;
  }

  Future<City> findOrCreateCityByName(
    String name, {
    double? lat,
    double? lng,
  }) async {
    final existing = await getCityByName(name);
    if (existing != null) return existing;

    final cleanName = name.trim().isEmpty ? 'Unknown City' : name.trim();
    final city = City(
      id: '',
      name: cleanName,
      image: '',
      lat: lat ?? 0,
      lng: lng ?? 0,
    );
    final id = await addCity(city);
    return city.copyWith(id: id);
  }

  // ──────────────────────────────────────────────────────────────
  //  LANDMARKS – Read
  // ──────────────────────────────────────────────────────────────

  bool _isVisibleLandmark(Landmark lm) =>
      !lm.hidden && !lm.isDuplicate && !lm.invalidPlace;

  Future<Landmark?> getLandmarkById(String placeId) async {
    final id = placeId.trim();
    if (id.isEmpty) return null;
    try {
      final doc = await _db.collection('landmarks').doc(id).get();
      if (!doc.exists || doc.data() == null) return null;
      return Landmark.fromJson(doc.data()!, doc.id);
    } catch (e) {
      print('getLandmarkById error: $e');
      return null;
    }
  }

  Stream<Landmark?> streamLandmarkById(String placeId) {
    final id = placeId.trim();
    if (id.isEmpty) return Stream.value(null);
    return _db.collection('landmarks').doc(id).snapshots().map((doc) {
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return Landmark.fromJson(data, doc.id);
    });
  }

  Future<List<Landmark>> getAllLandmarks() async {
    final snap = await _db.collection('landmarks').get();
    final list = snap.docs.map((d) => Landmark.fromJson(d.data(), d.id)).toList();
    return list.where(_isVisibleLandmark).toList();
  }

  Future<List<Landmark>> getLandmarksByCity(String cityId) async {
    if (cityId.trim().isEmpty) return [];
    final snap = await _db
        .collection('landmarks')
        .where('cityId', isEqualTo: cityId)
        .orderBy('name')
        .get();
    final list = snap.docs.map((d) => Landmark.fromJson(d.data(), d.id)).toList();
    return list.where(_isVisibleLandmark).toList();
  }

  /// Returns landmark doc ids that already use this hero [imageUrl] (for dedupe checks).
  Future<List<String>> findLandmarkIdsWithImageUrl(String imageUrl) async {
    final u = imageUrl.trim();
    if (u.isEmpty) return [];
    try {
      final snap =
          await _db.collection('landmarks').where('imageUrl', isEqualTo: u).limit(24).get();
      return snap.docs.map((d) => d.id).toList();
    } catch (e) {
      print('findLandmarkIdsWithImageUrl error: $e');
      return [];
    }
  }

  /// Manual/debug helper: logs duplicate image URLs and rows flagged for image review. Does not delete.
  Future<void> debugScanSuspiciousLandmarkImages() async {
    try {
      final snap = await _db.collection('landmarks').get();
      final byUrl = <String, List<Landmark>>{};
      for (final d in snap.docs) {
        final lm = Landmark.fromJson(d.data(), d.id);
        final u = lm.imageUrl.trim();
        if (u.isEmpty || !u.startsWith('http')) continue;
        byUrl.putIfAbsent(u, () => []).add(lm);
      }
      for (final e in byUrl.entries) {
        if (e.value.length < 2) continue;
        final names = e.value.map((x) => x.name).toSet();
        if (names.length <= 1) continue;
        if (kDebugMode) {
          debugPrint(
            '[Firebase] suspicious shared imageUrl used by ${e.value.length} places: '
            '${e.key.substring(0, e.key.length > 80 ? 80 : e.key.length)} names=$names',
          );
        }
      }
      for (final d in snap.docs) {
        final data = d.data();
        final review = (data['imageNeedsReview'] ?? false).toString().toLowerCase() == 'true';
        if (review && kDebugMode) {
          debugPrint('[Firebase] imageNeedsReview landmark ${d.id} ${data['name']}');
        }
      }
    } catch (e) {
      print('debugScanSuspiciousLandmarkImages error: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────
  //  LANDMARKS – Write
  // ──────────────────────────────────────────────────────────────
  Future<String> saveLandmark(Landmark landmark) async {
    final citiesSnap = await _db.collection('cities').get();
    final cities =
        citiesSnap.docs.map((d) => City.fromJson(d.data(), d.id)).toList();

    final resolution = CanonicalCityResolver.resolveForLandmark(landmark, cities);

    final resolvedName = resolution.canonicalCityName.trim();
    if (resolvedName.isEmpty || resolvedName.toLowerCase() == 'egypt') {
      throw Exception('Cannot save landmark without a specific city.');
    }

    City? actualCity;
    if (resolution.canonicalCityId.isNotEmpty) {
      for (final c in cities) {
        if (c.id == resolution.canonicalCityId) {
          actualCity = c;
          break;
        }
      }
    }
    actualCity ??= await findOrCreateCityByName(
      resolvedName,
      lat: landmark.lat != 0 ? landmark.lat : null,
      lng: landmark.lng != 0 ? landmark.lng : null,
    );

    final now = DateTime.now();
    var normalized = landmark.copyWith(
      cityId: actualCity.id,
      city: actualCity.name,
      description: landmark.description.trim().isNotEmpty
          ? landmark.description.trim()
          : landmark.shortDescription.trim(),
      shortDescription: landmark.shortDescription.trim().isNotEmpty
          ? landmark.shortDescription.trim()
          : landmark.description.trim(),
      createdAt: landmark.createdAt ?? now,
      updatedAt: now,
      imagePipelineVersion: landmark.imagePipelineVersion,
      imagesAreFallback: landmark.imagesAreFallback,
    );
    normalized = await _stripInvalidIncomingImages(normalized);

    final existing = await _db
        .collection('landmarks')
        .where('cityId', isEqualTo: normalized.cityId)
        .where('name', isEqualTo: normalized.name)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      final docId = existing.docs.first.id;
      final existingData = existing.docs.first.data();

      final existingLastAdminEditAt = (existingData?['lastAdminEditAt'] ?? '').toString().trim();
      final sources = (existingData?['sources'] is Map)
          ? Map<String, dynamic>.from(existingData!['sources'] as Map)
          : const <String, dynamic>{};
      final sourcesLastAdminEditAt = (sources['lastAdminEditAt'] ?? '').toString().trim();
      final existingAdminVerified =
          (existingData?['adminVerified'] ?? existingData?['isVerified'] ?? false).toString().trim().toLowerCase() == 'true';
      final existingCreatedByAdmin = (existingData?['createdByAdmin'] ?? false).toString().trim().toLowerCase() == 'true';
      final isAdminEdited = existingLastAdminEditAt.isNotEmpty ||
          sourcesLastAdminEditAt.isNotEmpty ||
          existingAdminVerified ||
          existingCreatedByAdmin ||
          (existingData?['lastAdminEditBy'] ?? '').toString().trim().isNotEmpty ||
          (existingData?['lastAdminEditByEmail'] ?? '').toString().trim().isNotEmpty;

      if (kDebugMode) {
        debugPrint(
          '[SaveLandmarkExisting] id=$docId name=${(existingData?['name'] ?? '').toString()} incoming=${normalized.name} lastAdminEditAt=$existingLastAdminEditAt isAdminEdited=$isAdminEdited',
        );
      }

      final updateMap = _buildMergeMap(existingData, normalized);
      if (updateMap.isNotEmpty) {
        await _db.collection('landmarks').doc(docId).set(updateMap, SetOptions(merge: true));
      }
      return docId;
    }

    // Merge into an existing row when search-generation produced a different
    // display string but the same normalized name / coordinates in-city.
    if (normalized.generatedBySearch) {
      try {
        final cityLms = await getLandmarksByCity(normalized.cityId);
        for (final other in cityLms) {
          if (PlaceSearchPipeline.isLikelyDuplicate(other, normalized)) {
            final snap = await _db.collection('landmarks').doc(other.id).get();
            final data = snap.data();
            if (data == null) continue;
            final updateMap = _buildMergeMap(data, normalized);
            if (updateMap.isNotEmpty) {
              await _db
                  .collection('landmarks')
                  .doc(other.id)
                  .set(updateMap, SetOptions(merge: true));
            }
            return other.id;
          }
        }
      } catch (e) {
        print('saveLandmark duplicate-scan error: $e');
      }
    }

    if (!PlaceSearchPipeline.validatePlaceForFirebaseSave(normalized)) {
      throw Exception('Landmark failed validation (name/category/city).');
    }

    final ref = await _db.collection('landmarks').add(normalized.toJson());
    return ref.id;
  }

  Map<String, dynamic> _buildMergeMap(
    Map<String, dynamic> existing,
    Landmark incoming,
  ) {
    // Protect admin-edited documents from being overwritten by background
    // seeding/enrichment merges.
    final existingLastAdminEditAt =
        (existing['lastAdminEditAt'] ?? '').toString().trim();
    final existingAdminVerified =
        (existing['adminVerified'] ?? existing['isVerified'] ?? false).toString().trim().toLowerCase() == 'true';
    final existingCreatedByAdmin =
        (existing['createdByAdmin'] ?? false).toString().trim().toLowerCase() == 'true';

    final sources = (existing['sources'] is Map)
        ? Map<String, dynamic>.from(existing['sources'] as Map)
        : const <String, dynamic>{};

    final existingSourcesLastAdminEditAt =
        (sources['lastAdminEditAt'] ?? '').toString().trim();

    final isAdminEdited =
        existingLastAdminEditAt.isNotEmpty ||
        existingSourcesLastAdminEditAt.isNotEmpty ||
        existingAdminVerified ||
        existingCreatedByAdmin ||
        (existing['lastAdminEditBy'] ?? '').toString().trim().isNotEmpty ||
        (existing['lastAdminEditByEmail'] ?? '').toString().trim().isNotEmpty;

    final map = <String, dynamic>{
      // keep city/cityId updates as default behavior for non-admin docs
      'city': incoming.city,
      'cityId': incoming.cityId,
    };

    if (isAdminEdited) {
      // Conservative merge: preserve all admin-controlled fields by NOT
      // overwriting them. Only write timestamps / enrichment pipeline
      // timestamps that are safe.
      final updatedAt = DateTime.now().toIso8601String();

      if (kDebugMode) {
        debugPrint(
          '[FirebaseMergeProtect] admin doc preserved name=${existing['name'] ?? ''} incoming=${incoming.name} mapKeys=${existing.keys.toList()}',
        );
      }


      // Only update empty-ish fields for admin docs.
      // If the admin already filled it, keep it.
      String existingVal(String key) =>
          (existing[key] ?? '').toString();

      String maybeFillEmpty(String key, String incomingVal) {
        final e = existingVal(key).trim();
        final n = incomingVal.trim();
        if (e.isEmpty && n.isNotEmpty) return n;
        return e;
      }

      // Debug: prove we hit the admin-protection branch and what keys we write.
      final existingNameDebug = (existing['name'] ?? '').toString();
      final incomingNameDebug = incoming.name.trim();

      // NOTE: mapKeys logged after the branch fills the map; this is filled later.


      void maybeFillEmptyOrListEmpty(String key, dynamic incomingVal) {
        final curr = existing[key];
        final currEmpty = curr == null ||
            (curr is String && curr.trim().isEmpty) ||
            (curr is List && curr.isEmpty);
        final incEmpty = incomingVal == null ||
            (incomingVal is String && incomingVal.trim().isEmpty) ||
            (incomingVal is List && incomingVal.isEmpty);

        if (currEmpty && !incEmpty) {
          map[key] = incomingVal;
        }
      }

      // Fill only when empty in DB.
      final newAddress = maybeFillEmpty('address', incoming.address);
      if (newAddress.trim().isNotEmpty) map['address'] = newAddress;

      final newDescription = maybeFillEmpty('description', incoming.description);
      if (newDescription.trim().isNotEmpty) map['description'] = newDescription;

      final newShortDescription =
          maybeFillEmpty('shortDescription', incoming.shortDescription);
      if (newShortDescription.trim().isNotEmpty) {
        map['shortDescription'] = newShortDescription;
      }

      final newFullDescription =
          maybeFillEmpty('fullDescription', incoming.fullDescription);
      if (newFullDescription.trim().isNotEmpty) {
        map['fullDescription'] = newFullDescription;
      }

      final newHistory = maybeFillEmpty('history', incoming.history);
      if (newHistory.trim().isNotEmpty) map['history'] = newHistory;

      final newOpeningHours =
          maybeFillEmpty('openingHours', incoming.openingHours);
      if (newOpeningHours.trim().isNotEmpty) {
        map['openingHours'] = newOpeningHours;
      }

      // Images: only fill when existing is empty.
      final existingHero = (existing['imageUrl'] ?? '').toString().trim();
      final existingMedia =
          List<String>.from(existing['mediaUrls'] as List? ?? const []);
      final incomingHasImages =
          incoming.mediaUrls.isNotEmpty || incoming.imageUrl.trim().isNotEmpty;
      if (incomingHasImages && existingHero.isEmpty && existingMedia.isEmpty) {
        final merged = _mergeMediaUrls(const [], incoming.mediaUrls, incoming.imageUrl);
        map['mediaUrls'] = merged;
        map['imageUrl'] = merged.isNotEmpty ? merged.first : incoming.imageUrl.trim();
        map['imagePipelineVersion'] = incoming.imagePipelineVersion;
        map['imagesAreFallback'] = incoming.imagesAreFallback;
      }

      // Rating: only fill if empty/0.
      final existingRating = ((existing['rating'] ?? 0) as num).toDouble();
      if (existingRating <= 0 && incoming.rating > 0) {
        map['rating'] = incoming.rating;
      }

      // Coordinates: only fill if empty/0.
      final existingLat = ((existing['lat'] ?? 0) as num).toDouble();
      final existingLng = ((existing['lng'] ?? 0) as num).toDouble();
      if ((existingLat == 0 || existingLng == 0) &&
          incoming.lat != 0 &&
          incoming.lng != 0) {
        map['lat'] = incoming.lat;
        map['lng'] = incoming.lng;
        map['location'] = '${incoming.lat}, ${incoming.lng}';
      }

      // Enrichment timestamps are safe to update.
      if (incoming.wikiEnrichedAt != null) {
        map['wikiEnrichedAt'] = incoming.wikiEnrichedAt!.toIso8601String();
      }
      if (incoming.imagesRefreshedAt != null) {
        map['imagesRefreshedAt'] = incoming.imagesRefreshedAt!.toIso8601String();
      }
      if (incoming.nearbyUpdatedAt != null) {
        map['nearbyUpdatedAt'] =
            incoming.nearbyUpdatedAt!.toIso8601String();
      }
      if (incoming.nearbyRefreshedAt != null) {
        map['nearbyRefreshedAt'] =
            incoming.nearbyRefreshedAt!.toIso8601String();
      }
      if (incoming.imagesFailedAt != null) {
        map['imagesFailedAt'] = incoming.imagesFailedAt!.toIso8601String();
      }
      if (incoming.imagesFailureReason.trim().isNotEmpty) {
        map['imagesFailureReason'] = incoming.imagesFailureReason.trim();
      }
      if (incoming.nearbyFailedAt != null) {
        map['nearbyFailedAt'] = incoming.nearbyFailedAt!.toIso8601String();
      }
      if (incoming.nearbyFailureReason.trim().isNotEmpty) {
        map['nearbyFailureReason'] = incoming.nearbyFailureReason.trim();
      }
      if (incoming.wikipediaUrl != null &&
          incoming.wikipediaUrl!.trim().isNotEmpty) {
        // preserve admin wikipediaUrl if filled; otherwise fill.
        final existingWiki = (existing['wikipediaUrl'] ?? '').toString().trim();
        if (existingWiki.isEmpty) {
          map['wikipediaUrl'] = incoming.wikipediaUrl!.trim();
        }
      }

      // Do not overwrite displayName/normalizedName/aliases/category/name.
      // updatedAt always updated.
      map['updatedAt'] = updatedAt;

      if (kDebugMode) {
        debugPrint(
          '[FirebaseMerge] preserve admin-edited fields '
          'place=${incoming.id.trim().isEmpty ? incoming.name : incoming.id} '
          'name=${incoming.name}',
        );
      }

      // If nothing besides city/cityId got added, avoid pointless write.
      // But keep timestamps; map likely not empty.
      return map;
    }

    void setText(String key, String newVal, String existingVal) {
      final n = newVal.trim();
      final e = existingVal.trim();
      if (n.isNotEmpty && n.length > e.length) map[key] = n;
    }

    setText('description', incoming.description, (existing['description'] ?? '').toString());
    setText('shortDescription', incoming.shortDescription, (existing['shortDescription'] ?? '').toString());
    setText('fullDescription', incoming.fullDescription, (existing['fullDescription'] ?? '').toString());
    setText('history', incoming.history, (existing['history'] ?? '').toString());
    setText('address', incoming.address, (existing['address'] ?? '').toString());
    setText('openingHours', incoming.openingHours, (existing['openingHours'] ?? '').toString());

    final existingMedia = List<String>.from(existing['mediaUrls'] as List? ?? const []);
    final existingVersion = int.tryParse((existing['imagePipelineVersion'] ?? 0).toString()) ?? 0;
    final existingFallback = (existing['imagesAreFallback'] ?? false).toString().toLowerCase() == 'true';
    final incomingHasImages = incoming.mediaUrls.isNotEmpty || incoming.imageUrl.trim().isNotEmpty;
    final shouldReplaceImages = incomingHasImages && (
      existingVersion < incoming.imagePipelineVersion ||
      existingMedia.isEmpty ||
      ((existing['imageUrl'] ?? '').toString().trim().isEmpty) ||
      (existingFallback && !incoming.imagesAreFallback)
    );

    final merged = shouldReplaceImages
        ? _mergeMediaUrls(const [], incoming.mediaUrls, incoming.imageUrl)
        : _mergeMediaUrls(existingMedia, incoming.mediaUrls, incoming.imageUrl);

    if (shouldReplaceImages || merged.length > existingMedia.length) {
      map['mediaUrls'] = merged;
      map['imageUrl'] = merged.isNotEmpty ? merged.first : incoming.imageUrl.trim();
      map['imagePipelineVersion'] = incoming.imagePipelineVersion;
      map['imagesAreFallback'] = incoming.imagesAreFallback;
    }

    final existingRating = ((existing['rating'] ?? 0) as num).toDouble();
    if (incoming.rating > existingRating) {
      map['rating'] = incoming.rating;
    }

    final existingLat = ((existing['lat'] ?? 0) as num).toDouble();
    final existingLng = ((existing['lng'] ?? 0) as num).toDouble();
    if ((existingLat == 0 || existingLng == 0) &&
        incoming.lat != 0 &&
        incoming.lng != 0) {
      map['lat'] = incoming.lat;
      map['lng'] = incoming.lng;
      map['location'] = '${incoming.lat}, ${incoming.lng}';
    }

    if (incoming.wikipediaUrl != null && incoming.wikipediaUrl!.trim().isNotEmpty) {
      map['wikipediaUrl'] = incoming.wikipediaUrl!.trim();
    }

    if (incoming.wikiEnrichedAt != null) {
      map['wikiEnrichedAt'] = incoming.wikiEnrichedAt!.toIso8601String();
    }
    if (incoming.imagesRefreshedAt != null) {
      map['imagesRefreshedAt'] = incoming.imagesRefreshedAt!.toIso8601String();
    }
    if (incoming.nearbyUpdatedAt != null) {
      map['nearbyUpdatedAt'] = incoming.nearbyUpdatedAt!.toIso8601String();
    }
    if (incoming.nearbyRefreshedAt != null) {
      map['nearbyRefreshedAt'] = incoming.nearbyRefreshedAt!.toIso8601String();
    }
    if (incoming.imagesFailedAt != null) {
      map['imagesFailedAt'] = incoming.imagesFailedAt!.toIso8601String();
    }
    if (incoming.imagesFailureReason.trim().isNotEmpty) {
      map['imagesFailureReason'] = incoming.imagesFailureReason.trim();
    }
    if (incoming.nearbyFailedAt != null) {
      map['nearbyFailedAt'] = incoming.nearbyFailedAt!.toIso8601String();
    }
    if (incoming.nearbyFailureReason.trim().isNotEmpty) {
      map['nearbyFailureReason'] = incoming.nearbyFailureReason.trim();
    }

    if (incoming.displayName.trim().isNotEmpty) {
      map['displayName'] = incoming.displayName.trim();
    }
    if (incoming.normalizedName.trim().isNotEmpty) {
      map['normalizedName'] = incoming.normalizedName.trim();
    }
    if (incoming.aliases.isNotEmpty) {
      final existingAliases = List<String>.from(existing['aliases'] as List? ?? const []);
      final merged = <String>{...existingAliases, ...incoming.aliases}
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (merged.isNotEmpty) map['aliases'] = merged;
    }
    if (incoming.generatedBySearch) {
      map['generatedBySearch'] = true;
    }
    map['updatedAt'] = DateTime.now().toIso8601String();

    if (kDebugMode) {
      debugPrint(
        '[FirebaseMergeNormal] normal merge name=${existing['name'] ?? ''} incoming=${incoming.name} mapKeys=${map.keys.toList()}',
      );
    }

    return map;
  }


  List<String> _mergeMediaUrls(
    List<String> old,
    List<String> incoming,
    String mainUrl,
  ) {
    final seen = <String>{};
    final result = <String>[];

    void add(String url) {
      final clean = url.trim();
      if (clean.isNotEmpty && seen.add(clean)) result.add(clean);
    }

    add(mainUrl);
    for (final u in old) add(u);
    for (final u in incoming) add(u);

    return result.take(6).toList();
  }

  Future<Map<String, String>> saveLandmarks(List<Landmark> landmarks) async {
    final result = <String, String>{};
    for (final lm in landmarks) {
      try {
        final docId = await saveLandmark(lm);
        result[lm.name] = docId;
      } catch (_) {}
    }
    return result;
  }

  // ──────────────────────────────────────────────────────────────
  //  ADMIN: Places / Review Queue / Users
  // ──────────────────────────────────────────────────────────────

  Future<List<Landmark>> adminGetPlaces({
    String cityId = '',
    String category = '',
    bool? hidden,
    bool? invalidPlace,
    bool? isDuplicate,
    bool? needsReview,
    int limit = 300,
  }) async {
    await requireAdmin();
    Query<Map<String, dynamic>> q = _db.collection('landmarks');
    if (cityId.trim().isNotEmpty) {
      q = q.where('cityId', isEqualTo: cityId.trim());
    }
    if (category.trim().isNotEmpty) {
      q = q.where('category', isEqualTo: category.trim());
    }
    final snap = await q.limit(limit).get();
    var list = snap.docs.map((d) => Landmark.fromJson(d.data(), d.id)).toList();
    if (hidden != null) list = list.where((e) => e.hidden == hidden).toList();
    if (invalidPlace != null) {
      list = list.where((e) => e.invalidPlace == invalidPlace).toList();
    }
    if (isDuplicate != null) {
      list = list.where((e) => e.isDuplicate == isDuplicate).toList();
    }
    if (needsReview != null) {
      list = list.where((e) => e.needsReview == needsReview).toList();
    }
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<List<Landmark>> adminGetReviewQueue({int limit = 300}) async {
    await requireAdmin();
    final snap = await _db.collection('landmarks').limit(limit).get();
    final all = snap.docs.map((d) => Landmark.fromJson(d.data(), d.id)).toList();
    return all.where((lm) {
      return lm.needsReview ||
          lm.cityNeedsReview ||
          lm.imageNeedsReview ||
          lm.outingNeedsReview ||
          lm.invalidPlace ||
          lm.isDuplicate ||
          lm.hidden;
    }).toList();
  }

  Future<String> adminUpsertPlace(
    Landmark place, {
    bool createdByAdmin = false,
    bool markVerified = false,
  }) async {
    await requireAdmin();

    final rawId = place.id.trim();
    final isEdit = rawId.isNotEmpty;

    final now = DateTime.now();
    final nowIso = now.toIso8601String();

    final docRef = isEdit
        ? _db.collection('landmarks').doc(rawId)
        : _db.collection('landmarks').doc();
    final docId = docRef.id;

    // IMPORTANT: Admin edits must update the exact Firestore landmark document
    // by document ID. Do not dedupe/merge-by-name/city during admin edits.

    if (isEdit) {
      final beforeSnap = await docRef.get();
      final beforeData = beforeSnap.data();
      if (!beforeSnap.exists) {
        throw Exception(
          'Admin edit failed: landmark doc does not exist for id=$rawId (edit must not create a new document).',
        );
      }


      final updateMap = <String, dynamic>{
        // editable fields (exactly what the editor controls)
        'name': place.name.trim(),
        'displayName': place.displayName.trim(),
        'normalizedName': place.normalizedName.trim(),
        'aliases': place.aliases,
        'city': place.city.trim(),
        'cityId': place.cityId.trim(),
        'category': place.category.trim(),
        'description': place.description.trim(),
        'shortDescription': place.shortDescription.trim(),
        'fullDescription': place.fullDescription.trim(),
        'history': place.history.trim(),
        'imageUrl': place.imageUrl.trim(),
        'mediaUrls': place.mediaUrls,
        'lat': place.lat,
        'lng': place.lng,
        'location': place.location.trim(),
        'address': place.address.trim(),
        'rating': place.rating,
        'openingHours': place.openingHours.trim(),
        'hidden': place.hidden,
        'needsReview': place.needsReview,
        'invalidPlace': place.invalidPlace,
        'invalidReason': place.invalidReason.trim(),
        'isDuplicate': place.isDuplicate,
        'duplicateOf': place.duplicateOf.trim(),
        'nearbyPlaces': place.nearbyPlaces,
        'sources': place.sources ?? <String, dynamic>{},

        // timestamps + admin metadata
        'updatedAt': nowIso,
        'lastAdminEditAt': nowIso,
        'lastAdminEditBy': currentUserId ?? '',
        'lastAdminEditByEmail': currentUserEmail,
      };

      if (markVerified) {
        updateMap['needsReview'] = false;

        // Key-existence rule: only set these flags if the keys already exist.
        final beforeKeys = beforeData?.keys.toSet() ?? const <String>{};
        if (beforeKeys.contains('cityNeedsReview')) {
          updateMap['cityNeedsReview'] = false;
        }
        if (beforeKeys.contains('imageNeedsReview')) {
          updateMap['imageNeedsReview'] = false;
        }
        if (beforeKeys.contains('outingNeedsReview')) {
          updateMap['outingNeedsReview'] = false;
        }
      }

      await docRef.set(updateMap, SetOptions(merge: true));

      if (kDebugMode) {
        debugPrint(
          '[AdminEditSaved] id=$docId name=${place.name} short=${place.shortDescription} lastAdminEditAt=${updateMap['lastAdminEditAt']}',
        );
      }

      await addAdminLog(
        actionType: 'place_updated',
        targetCollection: 'landmarks',
        targetId: docId,
        reason: 'admin direct upsert (edit by docId)',
        before: beforeData == null ? null : Map<String, dynamic>.from(beforeData),
        after: Map<String, dynamic>.from(updateMap)
          ..['status'] = 'success',
      );

      if (kDebugMode) {
        final vis = await verifyLandmarkVisibleInCity(docId);
        debugPrint(
          '[AdminSaveVerify] place=$docId cityId=${vis.cityId} visible=${vis.visible} reason=${vis.reason}',
        );
      }

      return docId;
    }

    // Create new doc when place.id is empty
    final createMap = <String, dynamic>{
      'id': docId,
      // editable fields
      'name': place.name.trim(),
      'displayName': place.displayName.trim(),
      'normalizedName': place.normalizedName.trim(),
      'aliases': place.aliases,
      'city': place.city.trim(),
      'cityId': place.cityId.trim(),
      'category': place.category.trim(),
      'description': place.description.trim(),
      'shortDescription': place.shortDescription.trim(),
      'fullDescription': place.fullDescription.trim(),
      'history': place.history.trim(),
      'imageUrl': place.imageUrl.trim(),
      'mediaUrls': place.mediaUrls,
      'lat': place.lat,
      'lng': place.lng,
      'location': place.location.trim(),
      'address': place.address.trim(),
      'rating': place.rating,
      'openingHours': place.openingHours.trim(),
      'hidden': place.hidden,
      'needsReview': place.needsReview,
      'invalidPlace': place.invalidPlace,
      'invalidReason': place.invalidReason.trim(),
      'isDuplicate': place.isDuplicate,
      'duplicateOf': place.duplicateOf.trim(),
      'nearbyPlaces': place.nearbyPlaces,
      'sources': place.sources ?? <String, dynamic>{},

      // admin metadata
      'createdByAdmin': createdByAdmin,
      'isVerified': markVerified,
      'createdAt': nowIso,
      'updatedAt': nowIso,
      'lastAdminEditAt': nowIso,
      'lastAdminEditBy': currentUserId ?? '',
      'lastAdminEditByEmail': currentUserEmail,
    };

    if (markVerified) {
      createMap['needsReview'] = false;
    }

    await docRef.set(createMap, SetOptions(merge: false));

    await addAdminLog(
      actionType: 'place_added',
      targetCollection: 'landmarks',
      targetId: docId,
      reason: 'admin direct upsert (create)',
      before: null,
      after: Map<String, dynamic>.from(createMap)
        ..['status'] = 'success',
    );

    if (kDebugMode) {
      final vis = await verifyLandmarkVisibleInCity(docId);
      debugPrint(
        '[AdminSaveVerify] place=$docId cityId=${vis.cityId} visible=${vis.visible} reason=${vis.reason}',
      );
    }

    return docId;
  }




  Future<void> adminUpdatePlaceFields(
    String placeId,
    Map<String, dynamic> fields, {
    String reason = '',
    String actionType = 'place_updated',
  }) async {
    await requireAdmin();

    final id = placeId.trim();
    if (id.isEmpty || fields.isEmpty) return;

    final ref = _db.collection('landmarks').doc(id);
    final beforeDoc = await ref.get();
    final before = beforeDoc.data();

    final now = DateTime.now().toIso8601String();
    final updateFields = Map<String, dynamic>.from(fields);
    updateFields['updatedAt'] = now;

    await ref.set(updateFields, SetOptions(merge: true));

    await addAdminLog(
      actionType: actionType,
      targetCollection: 'landmarks',
      targetId: id,
      reason: reason,
      before: before,
      after: {
        ...updateFields,
        'status': 'success',
      },
    );
  }

  Future<void> adminApprovePlace(String placeId) async {
    await adminUpdatePlaceFields(
      placeId,
      {
        'needsReview': false,
        'cityNeedsReview': false,
        'imageNeedsReview': false,
        'outingNeedsReview': false,
        'invalidPlace': false,
        'isDuplicate': false,
        'hidden': false,
        'isVerified': true,
        'approvedBy': currentUserId ?? '',
        'approvedAt': DateTime.now().toIso8601String(),
      },
      reason: 'admin approve',
      actionType: 'place_approved',
    );
    if (kDebugMode) {
      final vis = await verifyLandmarkVisibleInCity(placeId);
      debugPrint(
        '[AdminSaveVerify] place=$placeId cityId=${vis.cityId} visible=${vis.visible} reason=${vis.reason}',
      );
    }
  }

  Future<void> adminHidePlace(String placeId, {String reason = ''}) async {
  await adminUpdatePlaceFields(
    placeId,
    {
      'hidden': true,
      'hiddenReason': reason.isNotEmpty ? reason : 'admin hide',
      'needsReview': true,
    },
    reason: reason.isNotEmpty ? reason : 'admin hide',
    actionType: 'place_hidden',
  );
}



  

  Future<void> adminUnhidePlace(String placeId) async {
  await adminUpdatePlaceFields(
    placeId,
    {
      'hidden': false,
      'hiddenReason': '',
      'needsReview': false,
      'updatedAt': DateTime.now().toIso8601String(),
    },
    reason: 'admin unhide',
    actionType: 'place_unhidden',
  );
}

  Future<void> adminMarkInvalid(String placeId, String reason) async {
    await adminUpdatePlaceFields(
      placeId,
      {
        'invalidPlace': true,
        'invalidReason': reason.trim(),
        'needsReview': true,
        'hidden': true,
      },
      reason: reason,
      actionType: 'place_marked_invalid',
    );
  }

  Future<List<Map<String, dynamic>>> adminListUsers({int limit = 300}) async {
    await requireAdmin();
    final snap = await _db.collection('users').limit(limit).get();
    return snap.docs.map((d) {
      final m = d.data();
      return {
        'uid': d.id,
        'name': (m['name'] ?? '').toString(),
        'email': (m['email'] ?? '').toString(),
        'role': (m['role'] ?? 'user').toString(),
        'isBlocked': (m['isBlocked'] ?? false).toString().toLowerCase() == 'true',
      };
    }).toList();
  }

  Future<void> adminSetUserBlocked(String uid, bool blocked) async {
    await requireAdmin();
    final id = uid.trim();
    if (id.isEmpty) return;
    await _db.collection('users').doc(id).set({
      'isBlocked': blocked,
      'blockedAt': blocked ? DateTime.now().toIso8601String() : null,
      'blockedBy': blocked ? (currentUserId ?? '') : '',
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
    await addAdminLog(
      actionType: blocked ? 'user_blocked' : 'user_unblocked',
      targetCollection: 'users',
      targetId: id,
    );
  }

  Future<void> adminSetUserRole(String uid, String role) async {
    await requireAdmin();
    final id = uid.trim();
    final r = role.trim().toLowerCase();
    if (id.isEmpty || (r != 'admin' && r != 'user')) return;
    await _db.collection('users').doc(id).set({
      'role': r,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
    await addAdminLog(
      actionType: 'role_changed',
      targetCollection: 'users',
      targetId: id,
      reason: 'role=$r',
    );
  }

  Future<bool> cityHasLandmarks(String cityId) async {
    if (cityId.trim().isEmpty) return false;
    final snap = await _db
        .collection('landmarks')
        .where('cityId', isEqualTo: cityId)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  // ──────────────────────────────────────────────────────────────
  //  WIKIPEDIA ENRICHMENT
  // ──────────────────────────────────────────────────────────────
  Future<void> enrichLandmarkWithWikipedia({
    required String docId,
    required String shortDescription,
    required String fullDescription,
    required String history,
    required String wikipediaUrl,
  }) async {
    if (docId.trim().isEmpty) return;

    final updateMap = <String, dynamic>{};
    if (shortDescription.trim().isNotEmpty) {
      updateMap['description'] = shortDescription.trim();
      updateMap['shortDescription'] = shortDescription.trim();
    }
    if (fullDescription.trim().isNotEmpty) {
      updateMap['fullDescription'] = fullDescription.trim();
    }
    if (history.trim().isNotEmpty) {
      updateMap['history'] = history.trim();
    }
    if (wikipediaUrl.trim().isNotEmpty) {
      updateMap['wikipediaUrl'] = wikipediaUrl.trim();
    }
    updateMap['wikiEnrichedAt'] = DateTime.now().toIso8601String();

    if (updateMap.isNotEmpty) {
      await _db.collection('landmarks').doc(docId).set(updateMap, SetOptions(merge: true));
    }
  }

  // ──────────────────────────────────────────────────────────────
  //  MIGRATION UTILITY
  // ──────────────────────────────────────────────────────────────
  Future<void> fixCorruptLandmarkCityIds() async {
    print('Starting cityId migration...');
    final citiesSnap = await _db.collection('cities').get();
    final nameToDocId = <String, String>{};
    for (final doc in citiesSnap.docs) {
      final name = (doc.data()['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      nameToDocId[name.toLowerCase()] = doc.id;
    }

    final cities =
        citiesSnap.docs.map((d) => City.fromJson(d.data(), d.id)).toList();

    // Ensure Giza exists before fixing pyramid-related documents.
    final gizaCity = await findOrCreateCityByName('Giza');
    nameToDocId['giza'] = gizaCity.id;

    final validDocIds = nameToDocId.values.toSet();
    final landmarksSnap = await _db.collection('landmarks').get();
    final batch = _db.batch();
    int fixed = 0;

    for (final doc in landmarksSnap.docs) {
      final data = doc.data();
      final currentCityId = (data['cityId'] as String? ?? '').trim();
      final cityNameInDoc = (data['city'] as String? ?? '').trim();
      final name = (data['name'] as String? ?? '').trim();
      final address = (data['address'] as String? ?? '').trim();
      final description = (data['description'] as String? ?? '').trim();
      final shortDescription = (data['shortDescription'] as String? ?? '').trim();

      final fake = Landmark(
        id: doc.id,
        name: name,
        cityId: currentCityId,
        city: cityNameInDoc,
        category: (data['category'] as String? ?? 'tourist').trim(),
        description: description,
        shortDescription: shortDescription,
        fullDescription: (data['fullDescription'] as String? ?? '').trim(),
        history: (data['history'] as String? ?? '').trim(),
        imageUrl: (data['imageUrl'] as String? ?? '').trim(),
        mediaUrls: List<String>.from(data['mediaUrls'] as List? ?? const []),
        lat: ((data['lat'] ?? 0) as num).toDouble(),
        lng: ((data['lng'] ?? 0) as num).toDouble(),
        address: address,
        rating: ((data['rating'] ?? 0) as num).toDouble(),
        openingHours: (data['openingHours'] as String? ?? '').trim(),
        location: (data['location'] as String? ?? '').trim(),
      );

      final r = CanonicalCityResolver.resolveForLandmark(fake, cities);
      var correctDocId = r.canonicalCityId.trim();
      var displayCity = r.canonicalCityName.trim();

      if (correctDocId.isEmpty && displayCity.isNotEmpty) {
        correctDocId = nameToDocId[displayCity.toLowerCase()] ?? '';
      }
      if (correctDocId.isEmpty) {
        // Could not resolve — fall through to legacy id repair only.
      } else {
        for (final c in cities) {
          if (c.id == correctDocId) {
            displayCity = c.name;
            break;
          }
        }

        if (currentCityId != correctDocId ||
            cityNameInDoc.trim().toLowerCase() != displayCity.trim().toLowerCase()) {
          batch.update(doc.reference, {
            'cityId': correctDocId,
            'city': displayCity.isNotEmpty ? displayCity : cityNameInDoc,
          });
          fixed++;
          continue;
        }
      }

      if (!validDocIds.contains(currentCityId)) {
        final fallbackDocId = nameToDocId[cityNameInDoc.toLowerCase()];
        if (fallbackDocId != null) {
          batch.update(doc.reference, {'cityId': fallbackDocId});
          fixed++;
        }
      }
    }

    if (fixed > 0) {
      await batch.commit();
      print('Fixed $fixed corrupt city IDs.');
    } else {
      print('No corrupt city IDs found.');
    }
  }

  // ──────────────────────────────────────────────────────────────
  //  SAFE FIRESTORE CLEANUP (LAZY, LOADED-ONLY)
  // ──────────────────────────────────────────────────────────────

  /// Cleanup only one city batch (safe, does not scan the entire DB).
  Future<void> cleanupCityLandmarks(
    String cityId, {
    int maxPlacesPerRun = 30,
    int maxWrites = 100,
  }) async {
    if (cityId.trim().isEmpty) return;
    final raw = await _fetchLandmarksByCityRaw(
      cityId.trim(),
      limit: maxPlacesPerRun,
    );
    await cleanupLoadedLandmarks(
      raw,
      cityIdHint: cityId.trim(),
      force: false,
      maxPlaces: maxPlacesPerRun,
      maxWrites: maxWrites,
    );
  }

  /// Cleanup loaded landmarks (main safe entry point).
  Future<List<Landmark>> cleanupLoadedLandmarks(
    List<Landmark> loaded, {
    String? cityIdHint,
    bool force = false,
    int maxPlaces = 30,
    int maxWrites = 100,
  }) async {
    if (loaded.isEmpty) return const <Landmark>[];

    final now = DateTime.now();
    final skipAfter = const Duration(days: 7);

    final capped = loaded.take(maxPlaces).toList(growable: false);
    final targetCityLower =
        (cityIdHint ?? capped.first.cityId).trim().toLowerCase();
    if (targetCityLower.isEmpty) return const <Landmark>[];

    final citiesSnap = await _db.collection('cities').get();
    final cities =
        citiesSnap.docs.map((d) => City.fromJson(d.data(), d.id)).toList();

    bool recentlyValidated(Landmark lm) {
      final t = lm.dataValidatedAt;
      if (t == null) return false;
      return now.difference(t) <= skipAfter;
    }

    // In-memory working set
    final work = capped.map((e) => e).toList(growable: false);
    final Map<String, Landmark> byId = {for (final lm in work) lm.id: lm};

    // Track updates without overwriting sources with {}.
    final Map<String, Map<String, dynamic>> updateFields = {};

    int skippedCount = 0;
    int cityFixedCount = 0;
    int invalidHiddenCount = 0;
    int duplicatesHiddenCount = 0;
    int imagesCleanedCount = 0;

    void queue(String docId, Map<String, dynamic> fields) {
      if (docId.trim().isEmpty || fields.isEmpty) return;
      updateFields.update(
        docId,
        (prev) => {...prev, ...fields},
        ifAbsent: () => {...fields},
      );
    }

    // ── Step 1: city correctness + invalid/outings + hide flags ──
    for (final lm in work) {
      final id = lm.id.trim();
      if (id.isEmpty) continue;

      final tSkip = !force &&
          recentlyValidated(lm) &&
          !lm.hidden &&
          !lm.isDuplicate &&
          !lm.invalidPlace &&
          !lm.cityNeedsReview &&
          !lm.outingNeedsReview &&
          !lm.imageNeedsReview;

      if (tSkip) {
        skippedCount++;
        continue;
      }

      var next = lm;
      var changed = false;

      // City verification (include aliases in resolver input).
      final res = CanonicalCityResolver.resolveCanonicalCity(
        knownCities: cities,
        query: '${lm.name} ${lm.shortDescription} ${lm.aliases.join(' ')}',
        address: lm.address,
        cityName: lm.city,
        preferredCityId: lm.cityId,
        lat: lm.lat,
        lng: lm.lng,
      );
      final resolvedId = res.canonicalCityId.trim();
      final resolvedName = res.canonicalCityName.trim();

      final cityMismatch =
          lm.cityId.trim().toLowerCase() != resolvedId.toLowerCase() ||
              lm.city.trim().toLowerCase() != resolvedName.toLowerCase();

      if (cityMismatch) {
        final City? resolvedCity = cities.where((c) => c.id == resolvedId).isNotEmpty
            ? cities.firstWhere((c) => c.id == resolvedId)
            : null;

        final distKm = (resolvedCity != null && lm.hasValidCoordinates)
            ? _distanceKm(lm.lat, lm.lng, resolvedCity.lat, resolvedCity.lng)
            : null;

        final canMove = res.confidence >= 0.92 ||
            (res.confidence >= 0.85 && (distKm == null || distKm <= 120));

        if (resolvedId.isNotEmpty) {
          if (canMove) {
            next = next.copyWith(
              cityId: resolvedId,
              city: resolvedName.isNotEmpty ? resolvedName : lm.city,
              cityNeedsReview: false,
              cityReviewReason: '',
            );
            changed = true;
            cityFixedCount++;

          } else {
            next = next.copyWith(
              cityNeedsReview: true,
              cityReviewReason: 'Could not verify city',
            );
            changed = true;
          }
        } else {
          next = next.copyWith(
            cityNeedsReview: true,
            cityReviewReason: 'Could not verify city',
          );
          changed = true;
        }
      }

      // Invalid/random detection
      final catAllowed = PlaceCategoryNormalizer.isAllowed(
        next.category,
        contextText: '${next.name} ${next.description} ${next.shortDescription}',
      );
      final baseValid = PlaceSearchPipeline.validatePlaceForFirebaseSave(next);
      final broken = PlaceSearchPipeline.isBrokenTransliterationName(next.name);
      final noCoordsAndNoAddress =
          (!next.hasValidCoordinates && next.address.trim().isEmpty && next.location.trim().isEmpty);
      final hay = '${next.name} ${next.shortDescription} ${next.description} ${next.address} ${next.location}'
          .toLowerCase();
      final looksServicePoint = RegExp(
        r'\b(office|offices|hospital|school|university|college|academy|kindergarten|police|embassy|consulate|ministry|government|court|courthouse|clinic|pharmacy|atm only|bank branch|bank|warehouse|factory|residential|apartment|compound)\b',
        caseSensitive: false,
      ).hasMatch(hay);

      var invalidPlace = next.invalidPlace;
      var invalidReason = next.invalidReason;
      var outingNeedsReview = next.outingNeedsReview;
      var outingNeedsReviewReason = next.outingNeedsReviewReason;
      var hidden = next.hidden;

      if (!baseValid || !catAllowed || broken || noCoordsAndNoAddress || looksServicePoint) {
        invalidPlace = true;
        invalidReason = !baseValid
            ? 'Failed base place validation'
            : !catAllowed
                ? 'Category not allowed'
                : broken
                    ? 'Broken transliteration / Franco-garbage name'
                    : looksServicePoint
                        ? 'Non-visitor / service point token match'
                        : 'Missing coordinates and address';
        hidden = true;
      }

      if (next.category.trim().toLowerCase() == 'outing') {
        if (!PlaceSearchPipeline.isVerifiedVisitorOutingLandmark(next)) {
          invalidPlace = true;
          invalidReason = 'Outing place not visitor-friendly or not verified';
          outingNeedsReview = true;
          outingNeedsReviewReason =
              'Outing place not visitor-friendly or not verified';
          hidden = true;
        }
      }

      if (invalidPlace != next.invalidPlace ||
          invalidReason.trim() != next.invalidReason.trim() ||
          outingNeedsReview != next.outingNeedsReview ||
          outingNeedsReviewReason.trim() != next.outingNeedsReviewReason.trim() ||
          hidden != next.hidden) {
        next = next.copyWith(
          invalidPlace: invalidPlace,
          invalidReason: invalidReason,
          outingNeedsReview: outingNeedsReview,
          outingNeedsReviewReason: outingNeedsReviewReason,
          hidden: hidden || invalidPlace,
          needsReview: true,
        );
        changed = true;
        if (invalidPlace) invalidHiddenCount++;
      }

      if (changed) {
        queue(id, {
          'cityId': next.cityId,
          'city': next.city,
          'cityNeedsReview': next.cityNeedsReview,
          'cityReviewReason': next.cityReviewReason,
          'invalidPlace': next.invalidPlace,
          'invalidReason': next.invalidReason,
          'outingNeedsReview': next.outingNeedsReview,
          'outingNeedsReviewReason': next.outingNeedsReviewReason,
          'hidden': next.hidden,
          'needsReview': next.needsReview,
          'updatedAt': now.toIso8601String(),
          'dataValidatedAt': now.toIso8601String(),
        });
        byId[id] = next;
      }
    }

    // Visible candidates for duplicates merge:
    // only within target city page.
    final visibleForDup = byId.values.where((lm) {
      if (lm.cityId.trim().toLowerCase() != targetCityLower) return false;
      if (lm.hidden || lm.invalidPlace || lm.isDuplicate) return false;
      return true;
    }).toList();

    // ── Step 2: duplicate detection + merge (loaded-only) ──
    final ids = visibleForDup.map((e) => e.id).toList();
    final parent = List.generate(ids.length, (i) => i);

    int find(int x) {
      var v = x;
      while (parent[v] != v) {
        parent[v] = parent[parent[v]];
        v = parent[v];
      }
      return v;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[rb] = ra;
    }

    bool shareMediaOrHero(Landmark a, Landmark b) {
      final heroA = a.imageUrl.trim();
      final heroB = b.imageUrl.trim();
      if (heroA.isNotEmpty && heroA == heroB) return true;
      if (heroA.isNotEmpty &&
          b.mediaUrls.any((u) => u.trim().isNotEmpty && u.trim() == heroA)) {
        return true;
      }
      final setA = a.mediaUrls.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
      return b.mediaUrls.map((e) => e.trim()).any((u) => u.isNotEmpty && setA.contains(u));
    }

    for (var i = 0; i < visibleForDup.length; i++) {
      for (var j = i + 1; j < visibleForDup.length; j++) {
        final a = visibleForDup[i];
        final b = visibleForDup[j];
        final likely =
            PlaceSearchPipeline.isLikelyDuplicate(a, b) || shareMediaOrHero(a, b);
        if (likely) union(i, j);
      }
    }

    final Map<int, List<Landmark>> clusters = {};
    for (var i = 0; i < visibleForDup.length; i++) {
      final r = find(i);
      clusters.putIfAbsent(r, () => []).add(visibleForDup[i]);
    }

    int imageScore(Landmark lm) {
      var s = 0;
      if (lm.imageUrl.trim().isNotEmpty) s += 10;
      s += lm.mediaUrls.length.clamp(0, 6);
      if (lm.wikipediaUrl?.trim().isNotEmpty ?? false) s += 3;
      if (lm.history.trim().isNotEmpty) s += 1;
      return s;
    }

    Landmark pickBest(List<Landmark> group) {
      group.sort((a, b) => imageScore(b).compareTo(imageScore(a)));
      return group.first;
    }

    final Set<String> duplicateClusterIds = <String>{};

    for (final group in clusters.values) {
      if (group.length < 2) continue;
      final best = pickBest(group);
      final clusterIds = group.map((e) => e.id).toSet();
      duplicateClusterIds.addAll(clusterIds);

      for (final other in group) {
        if (other.id == best.id) continue;

        // Merge a few fields conservatively into best.
        final mergedAliases = <String>{
          ...best.aliases,
          ...other.aliases,
        }.toList();

        final mergedDescription = best.description.trim().isNotEmpty &&
                other.description.trim().isNotEmpty &&
                best.description.trim().length >= other.description.trim().length
            ? best.description
            : (other.description.trim().isNotEmpty ? other.description : best.description);

        final mergedHistory = best.history.trim().isNotEmpty &&
                other.history.trim().isNotEmpty &&
                best.history.trim().length >= other.history.trim().length
            ? best.history
            : (other.history.trim().isNotEmpty ? other.history : best.history);

        final mergedOpeningHours =
            best.openingHours.trim().isNotEmpty ? best.openingHours : other.openingHours;

        final mergedRating = other.rating > best.rating ? other.rating : best.rating;

        // Only fill images if best has none.
        var mergedBest = best;
        if (best.imageUrl.trim().isEmpty && other.imageUrl.trim().isNotEmpty) {
          mergedBest = mergedBest.copyWith(
            imageUrl: other.imageUrl.trim(),
            mediaUrls: other.mediaUrls,
          );
        }
        if (best.mediaUrls.isEmpty && other.mediaUrls.isNotEmpty) {
          mergedBest = mergedBest.copyWith(mediaUrls: other.mediaUrls);
        }

        mergedBest = mergedBest.copyWith(
          aliases: mergedAliases,
          description: mergedDescription,
          history: mergedHistory,
          openingHours: mergedOpeningHours,
          rating: mergedRating,
          updatedAt: now,
          dataValidatedAt: now,
        );

        byId[best.id] = mergedBest;
        queue(best.id, {
          'aliases': mergedBest.aliases,
          'description': mergedBest.description,
          'history': mergedBest.history,
          'openingHours': mergedBest.openingHours,
          'rating': mergedBest.rating,
          'imageUrl': mergedBest.imageUrl,
          'mediaUrls': mergedBest.mediaUrls,
          'updatedAt': now.toIso8601String(),
          'dataValidatedAt': now.toIso8601String(),
        });

        // Hide duplicate doc.
        queue(other.id, {
          'hidden': true,
          'isDuplicate': true,
          'duplicateOf': best.id,
          'needsReview': true,
          'updatedAt': now.toIso8601String(),
          'dataValidatedAt': now.toIso8601String(),
        });
        duplicatesHiddenCount++;
        byId[other.id] = other.copyWith(
          hidden: true,
          isDuplicate: true,
          duplicateOf: best.id,
          needsReview: true,
          updatedAt: now,
          dataValidatedAt: now,
        );
      }
    }

    // ── Step 3: image validation cleanup (loaded-visible docs only) ──
    int imageUpdates = 0;
    final visibleNow = byId.values.where((lm) {
      if (lm.cityId.trim().toLowerCase() != targetCityLower) return false;
      if (lm.hidden || lm.invalidPlace || lm.isDuplicate) return false;
      return true;
    }).toList();

    for (final lm in visibleNow) {
      if (imageUpdates * 3 >= maxWrites) break;
      final docId = lm.id.trim();
      if (docId.isEmpty) continue;

      if (imageUpdates > maxPlaces) break;

      final candidateUrls = <String>[];
      final hero = lm.imageUrl.trim();
      if (hero.isNotEmpty) candidateUrls.add(hero);
      for (final u in lm.mediaUrls) {
        final t = u.trim();
        if (t.isEmpty || candidateUrls.contains(t)) continue;
        candidateUrls.add(t);
      }

      if (candidateUrls.isEmpty) continue;

      final metaBase =
          '${lm.name} ${lm.city} ${lm.category} ${lm.address} ${lm.shortDescription}';

      final clusterOwners = <String>{lm.id};
      // Allow images only inside this duplicate cluster (if any).
      if (lm.isDuplicate) {
        if (lm.duplicateOf.trim().isNotEmpty) clusterOwners.add(lm.duplicateOf.trim());
      }
      // For safety: allow any owner id that belongs to the same
      // duplicateClusterIds set.
      final accepted = <String>[];
      var anyChange = false;
      for (final url in candidateUrls) {
        if (accepted.length >= 6) break;
        final clean = url.trim();
        if (!_imageValidatorNonNull.validateImageCandidateForPlace(
          url: clean,
          metaText: '$metaBase $clean',
          placeName: lm.name,
          cityName: lm.city,
          category: lm.category,
        )) {
          anyChange = true;
          continue;
        }

        final owners = await findLandmarkIdsWithImageUrl(clean);
        final usedElsewhere = owners.any((oid) {
          final other = oid.trim();
          if (other.isEmpty) return false;
          if (other == lm.id) return false;
          if (duplicateClusterIds.contains(other)) return false;
          return true;
        });

        if (usedElsewhere) {
          anyChange = true;
          continue;
        }

        accepted.add(clean);
      }

      if (accepted.isEmpty) {
        if (lm.imageUrl.trim().isNotEmpty || lm.mediaUrls.isNotEmpty) {
          if (kDebugMode) {
            debugPrint(
              '[ImageEnrichUpdate] doc=$docId fields={imageUrl, mediaUrls, imageNeedsReview, imageRejectedAt, imageRejectedReason, imagesValidatedAt, updatedAt}',
            );
          }
          queue(docId, {
            'imageUrl': '',
            'mediaUrls': const [],
            'imageNeedsReview': true,
            'imageRejectedAt': now.toIso8601String(),
            'imageRejectedReason': 'no_valid_images_after_cleanup',
            'imagesValidatedAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
          });

          anyChange = true;
          imagesCleanedCount++;
        }
      
      // image enrichment debug: do not log in normal image case to avoid spam

      } else {
        final newHero = accepted.first;
        final newMedia = accepted;
        final heroChanged = lm.imageUrl.trim() != newHero;
        final mediaChanged =
            lm.mediaUrls.length != newMedia.length ||
                !lm.mediaUrls.every((u) => newMedia.contains(u.trim()));
        if (anyChange || heroChanged || mediaChanged) {
          queue(docId, {
            'imageUrl': newHero,
            'mediaUrls': newMedia,
            'imageNeedsReview': false,
            'imagesValidatedAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
          });
          imagesCleanedCount++;
        }
      }

      if (kDebugMode && updateFields.isNotEmpty) {
        // log once at the end (to avoid spamming).
      }
      imageUpdates++;
    }

    // ── Step 4: apply queued updates (batch) ──
    if (updateFields.isEmpty) {
      return visibleNow.where((lm) => _isVisibleLandmark(lm)).toList();
    }

    int writes = 0;
    final batch = _db.batch();
    for (final entry in updateFields.entries) {
      if (writes >= maxWrites) break;
      batch.update(
        _db.collection('landmarks').doc(entry.key),
        entry.value,
      );
      writes++;
    }

    if (writes > 0) await batch.commit();

    // Return final visible list for current city page.
    final result = byId.values.where((lm) {
      if (lm.cityId.trim().toLowerCase() != targetCityLower) return false;
      return _isVisibleLandmark(lm);
    }).toList();

    if (kDebugMode) {
      debugPrint(
        '[Cleanup] done cityId=$targetCityLower scanned=${loaded.length} '
        'queuedUpdates=${updateFields.length} returned=${result.length} '
        'skipped=$skippedCount cityFixed=$cityFixedCount '
        'invalidHidden=$invalidHiddenCount duplicatesHidden=$duplicatesHiddenCount '
        'imagesCleaned=$imagesCleanedCount',
      );
    }
    return result;
  }

  Future<void> cleanupDuplicatesForCity(String cityId,
      {int maxPlacesPerRun = 60}) async {
    await cleanupCityLandmarks(
      cityId,
      maxPlacesPerRun: maxPlacesPerRun,
      maxWrites: 120,
    );
  }

  Future<Map<String, dynamic>> adminRunCleanupCity(
    String cityId, {
    int maxPlacesPerRun = 30,
  }) async {
    await requireAdmin();
    final raw = await _fetchLandmarksByCityRaw(cityId, limit: maxPlacesPerRun);
    final beforeById = {for (final lm in raw) lm.id: lm};
    final beforeVisible = raw.where(_isVisibleLandmark).length;
    await cleanupLoadedLandmarks(
      raw,
      cityIdHint: cityId,
      force: true,
      maxPlaces: maxPlacesPerRun,
      maxWrites: 120,
    );
    final after = await _fetchLandmarksByCityRaw(cityId, limit: maxPlacesPerRun);
    final afterVisible = after.where(_isVisibleLandmark).length;
    int cityFixed = 0;
    int duplicatesHidden = 0;
    int invalidHidden = 0;
    int imagesCleaned = 0;
    int changed = 0;
    for (final a in after) {
      final b = beforeById[a.id];
      if (b == null) continue;
      final changedCity = a.cityId.trim() != b.cityId.trim() ||
          a.city.trim().toLowerCase() != b.city.trim().toLowerCase();
      if (changedCity) cityFixed++;
      if (!b.isDuplicate && a.isDuplicate && a.hidden) duplicatesHidden++;
      if ((!b.invalidPlace || !b.hidden) && a.invalidPlace && a.hidden) {
        invalidHidden++;
      }
      final imageChanged = a.imageUrl.trim() != b.imageUrl.trim() ||
          a.mediaUrls.join('|') != b.mediaUrls.join('|');
      if (imageChanged) imagesCleaned++;
      if (changedCity ||
          (!b.isDuplicate && a.isDuplicate) ||
          (!b.invalidPlace && a.invalidPlace) ||
          imageChanged) {
        changed++;
      }
    }
    final summary = <String, dynamic>{
      'scanned': raw.length,
      'visibleBefore': beforeVisible,
      'visibleAfter': afterVisible,
      'hiddenOrInvalidOrDup': raw.length - afterVisible,
      'cityFixed': cityFixed,
      'duplicatesHidden': duplicatesHidden,
      'invalidHidden': invalidHidden,
      'imagesCleaned': imagesCleaned,
      'skipped': (raw.length - changed).clamp(0, raw.length),
      'cityId': cityId,
    };
    await addAdminLog(
      actionType: 'cleanup_city_run',
      targetCollection: 'cities',
      targetId: cityId,
      after: summary,
    );
    return summary;
  }

  Future<Map<String, dynamic>> adminRunCleanupAllCities({
    int maxCities = 50,
    int maxPlacesPerCity = 30,
  }) async {
    await requireAdmin();
    final cities = await getCities();
    final capped = cities.take(maxCities).toList();
    int scanned = 0;
    int visibleAfter = 0;
    for (final c in capped) {
      final s = await adminRunCleanupCity(
        c.id,
        maxPlacesPerRun: maxPlacesPerCity,
      );
      scanned += (s['scanned'] as int? ?? 0);
      visibleAfter += (s['visibleAfter'] as int? ?? 0);
    }
    final summary = {
      'cities': capped.length,
      'scanned': scanned,
      'visibleAfter': visibleAfter,
    };
    await addAdminLog(
      actionType: 'cleanup_all_cities_run',
      targetCollection: 'cities',
      targetId: 'all',
      after: summary,
    );
    return summary;
  }

  Future<void> cleanupWrongCityAssignments(String cityId,
      {int maxPlacesPerRun = 60}) async {
    await cleanupCityLandmarks(
      cityId,
      maxPlacesPerRun: maxPlacesPerRun,
      maxWrites: 120,
    );
  }

  Future<Landmark?> cleanupSingleLandmark(String landmarkId,
      {bool force = false}) async {
    final id = landmarkId.trim();
    if (id.isEmpty) return null;
    final doc = await _db.collection('landmarks').doc(id).get();
    if (!doc.exists || doc.data() == null) return null;
    final lm = Landmark.fromJson(doc.data()!, doc.id);
    final cleaned = await cleanupLoadedLandmarks(
      [lm],
      cityIdHint: lm.cityId,
      force: force,
      maxPlaces: 1,
      maxWrites: 20,
    );
    return cleaned.isNotEmpty ? cleaned.first : null;
  }

  Future<List<Landmark>> _fetchLandmarksByCityRaw(String cityId,
      {required int limit}) async {
    final snap = await _db
        .collection('landmarks')
        .where('cityId', isEqualTo: cityId)
        .limit(limit)
        .get();
    return snap.docs.map((d) => Landmark.fromJson(d.data(), d.id)).toList();
  }

  Future<void> saveRemoteNearbyPlaces({
    required String cityName,
    required List<Map<String, dynamic>> places,
  }) async {
    for (final item in places) {
      try {
        final name = (item['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        final cityDoc = await findOrCreateCityByName(cityName);
        final existing = await _db
            .collection('landmarks')
            .where('cityId', isEqualTo: cityDoc.id)
            .where('name', isEqualTo: name)
            .limit(1)
            .get();

        if (existing.docs.isNotEmpty) continue;

        await _db.collection('landmarks').add({
          'name': name,
          'city': cityName,
          'cityId': cityDoc.id,
          'category': (item['category'] ?? 'tourist').toString(),
          'description': (item['shortDescription'] ?? '').toString(),
          'shortDescription': (item['shortDescription'] ?? '').toString(),
          'fullDescription': (item['fullDescription'] ?? '').toString(),
          'history': (item['history'] ?? '').toString(),
          'imageUrl': (item['imageUrl'] ?? '').toString(),
          'mediaUrls': item['mediaUrls'] ?? [],
          'lat': ((item['lat'] ?? 0) as num).toDouble(),
          'lng': ((item['lng'] ?? 0) as num).toDouble(),
          'address': (item['address'] ?? cityName).toString(),
          'rating': ((item['rating'] ?? 0) as num).toDouble(),
          'openingHours': (item['openingHours'] ?? '').toString(),
          'location': '',
          'createdAt': DateTime.now().toIso8601String(),
          'nearbyUpdatedAt':
              (item['nearbyRefreshedAt'] ?? DateTime.now().toIso8601String()),
        });
      } catch (_) {}
    }
  }

  // ──────────────────────────────────────────────────────────────
  //  GEOMETRY
  // ──────────────────────────────────────────────────────────────
  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    if (lat1 == 0 || lng1 == 0 || lat2 == 0 || lng2 == 0) {
      return double.infinity;
    }
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            (math.sin(dLng / 2) * math.sin(dLng / 2));
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degToRad(double deg) => deg * (math.pi / 180.0);
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

  @override
  String toString() => toJson().toString();
}
