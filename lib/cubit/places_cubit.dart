// ============================================================
//  cubit/places_cubit.dart
//
//  Manages:
//    • City list loading
//    • Per-city landmark loading (with full pipeline)
//    • All-landmarks loading for "View All Places"
//    • Search / filter
// ============================================================

import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/firebase_service.dart';
import '../services/pipe_service.dart';
 import '../../../cubit/place_state.dart';
 import '../../../models.dart/createCity_model.dart';
 import '../../../models.dart/landmark_model.dart';
// ============================================================
//  cubit/places_cubit.dart
//
//  FIX: loadLandmarksForCity() now auto-triggers the full
//       pipeline when a city has no cached landmarks.
//       No admin action needed — happens transparently.
// ============================================================

class PlacesCubit extends Cubit<PlacesState> {
  final FirebaseService _firebase;
  final DataPipelineService _pipeline;

  final Map<String, List<Landmark>> _landmarkCache = {};
  List<City> _cities = [];

  PlacesCubit({
    FirebaseService? firebase,
    DataPipelineService? pipeline,
  })  : _firebase = firebase ?? FirebaseService(),
        _pipeline = pipeline ?? DataPipelineService(),
        super(PlacesInitial());

  // ── Load city list ────────────────────────────────────────────────────────
  Future<void> loadCities() async {
    emit(CitiesLoading());
    try {
      _cities = await _firebase.getCities();
      emit(CitiesSuccess(_cities));
    } catch (e) {
      emit(CitiesFailure('Could not load cities: $e'));
    }
  }

  // ── Load landmarks for a city ─────────────────────────────────────────────
  // AUTO-PIPELINE: if city has no data, the pipeline runs automatically.
  // The user sees progress messages like "Fetching from Google…" etc.
  Future<void> loadLandmarksForCity(
  City city, {
  bool forceRefresh = false,
}) async {
  if (!forceRefresh && _landmarkCache.containsKey(city.id)) {
    emit(LandmarksSuccess(
      landmarks: _landmarkCache[city.id]!,
      cityId: city.id,
    ));
    return;
  }

  print('🔍 Loading landmarks for: ${city.name} (id: ${city.id})');
  
  if (!isClosed) emit(LandmarksLoading('Loading "${city.name}"…')); // FIX: guard

  try {
    final landmarks = await _pipeline.fetchOrLoadLandmarks(
      city,
      forceRefresh: forceRefresh,
      onProgress: (msg) {
        if (!isClosed) emit(LandmarksLoading(msg));
      },
    );

    _landmarkCache[city.id] = landmarks;
    if (!isClosed) emit(LandmarksSuccess(landmarks: landmarks, cityId: city.id)); // FIX
  } catch (e) {
    if (!isClosed) emit(LandmarksFailure('Failed to load places for ${city.name}: $e')); // FIX
  }
}

  // ── Load ALL landmarks (for "View All" screen) ────────────────────────────
  Future<void> loadAllLandmarks() async {
    emit(AllLandmarksLoading());
    try {
      final landmarks = await _firebase.getAllLandmarks();
      emit(AllLandmarksSuccess(landmarks));
    } catch (e) {
      emit(AllLandmarksFailure('Failed to load all places: $e'));
    }
  }

  // ── Filter helpers (synchronous, called from UI) ──────────────────────────
  List<Landmark> filterBySearch(List<Landmark> landmarks, String query) {
    if (query.trim().isEmpty) return landmarks;
    final q = query.toLowerCase();
    return landmarks
        .where((lm) =>
            lm.name.toLowerCase().contains(q) ||
            lm.shortDescription.toLowerCase().contains(q) ||
            lm.address.toLowerCase().contains(q))
        .toList();
  }

  List<Landmark> filterByCategory(List<Landmark> landmarks, String category) {
    if (category == 'all') return landmarks;
    return landmarks.where((lm) => lm.category == category).toList();
  }

  // ── Accessors ─────────────────────────────────────────────────────────────
  List<City> get cities => _cities;

  List<Landmark> cachedLandmarks(String cityId) =>
      _landmarkCache[cityId] ?? [];
}