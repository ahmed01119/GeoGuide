// ============================================================
//  cubit/places_state.dart
//
//  States for the PlacesCubit (city loading + pipeline)
// ============================================================


 import '../../../models.dart/createCity_model.dart';
 import '../../../models.dart/landmark_model.dart';

abstract class PlacesState {}

class PlacesInitial extends PlacesState {}

// ── Cities ────────────────────────────────────────────────
class CitiesLoading extends PlacesState {}

class CitiesSuccess extends PlacesState {
  final List<City> cities;
  CitiesSuccess(this.cities);
}

class CitiesFailure extends PlacesState {
  final String message;
  CitiesFailure(this.message);
}

// ── Landmarks / Pipeline ──────────────────────────────────
class LandmarksLoading extends PlacesState {
  /// Human-readable status message, e.g. "Fetching Wikipedia…"
  final String statusMessage;
  LandmarksLoading([this.statusMessage = 'Loading places…']);
}

class LandmarksSuccess extends PlacesState {
  final List<Landmark> landmarks;
  final String cityId;
  LandmarksSuccess({required this.landmarks, required this.cityId});
}

class LandmarksFailure extends PlacesState {
  final String message;
  LandmarksFailure(this.message);
}

// ── All landmarks (used by the "View All Places" screen) ──
class AllLandmarksLoading extends PlacesState {}

class AllLandmarksSuccess extends PlacesState {
  final List<Landmark> landmarks;
  AllLandmarksSuccess(this.landmarks);
}

class AllLandmarksFailure extends PlacesState {
  final String message;
  AllLandmarksFailure(this.message);
}