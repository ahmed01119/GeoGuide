// ignore_for_file: file_names

import '../models.dart/createCity_model.dart';
import '../models.dart/landmark_model.dart';

class UserState {}

final class UserInitial extends UserState {}

// ── Login ─────────────────────────────────────────────────────────────────
final class LoginInSuccess extends UserState {
  final String message;
  LoginInSuccess({required this.message});
}

final class LoginInLoading extends UserState {}

final class LoginInFailure extends UserState {
  final String errMessage;
  LoginInFailure({required this.errMessage});
}

// ── Sign Up ───────────────────────────────────────────────────────────────
final class SignUpSuccess extends UserState {
  final String message;
  SignUpSuccess({required this.message});
}

final class SignUpLoading extends UserState {}

final class SignUpFailure extends UserState {
  final String errMessage;
  SignUpFailure({required this.errMessage});
}

// ── Forgot / Change Password ──────────────────────────────────────────────
class ForgetPasswordLoading extends UserState {}

class ForgetPasswordSuccess extends UserState {
  final String message;
  ForgetPasswordSuccess({required this.message});
}

class ForgetPasswordFailure extends UserState {
  final String errMessage;
  ForgetPasswordFailure({required this.errMessage});
}

class ChangePasswordLoading extends UserState {}

class ChangePasswordSuccess extends UserState {
  final String message;
  ChangePasswordSuccess({required this.message});
}

class ChangePasswordFailure extends UserState {
  final String errMessage;
  ChangePasswordFailure({required this.errMessage});
}

// ── Get All Cities ────────────────────────────────────────────────────────
final class GetAllCitiesLoading extends UserState {}

final class GetAllCitiesSuccess extends UserState {
  final List<City> cities;
  GetAllCitiesSuccess({required this.cities});
}

final class GetAllCitiesFailure extends UserState {
  final String errMessage;
  GetAllCitiesFailure({required this.errMessage});
}

// ── Places ────────────────────────────────────────────────────────────────
class GetPlacesLoading extends UserState {}

class GetPlacesSuccess extends UserState {
  final List<Landmark> places;
  GetPlacesSuccess(this.places);
}

class GetPlacesFailure extends UserState {
  final String error;
  GetPlacesFailure(this.error);
}

// ── Landmarks ─────────────────────────────────────────────────────────────
final class CreateLandmarkLoading extends UserState {}

final class CreateLandmarkSuccess extends UserState {
  final String message;
  final Landmark landmark;
  CreateLandmarkSuccess({required this.message, required this.landmark});
}

final class CreateLandmarkFailure extends UserState {
  final String errMessage;
  CreateLandmarkFailure({required this.errMessage});
}

final class GetAllLandmarksLoading extends UserState {}

final class GetAllLandmarksSuccess extends UserState {
  final List<Landmark> landmarks;
  GetAllLandmarksSuccess({required this.landmarks});
}

final class GetAllLandmarksFailure extends UserState {
  final String errMessage;
  GetAllLandmarksFailure({required this.errMessage});
}

final class GetLandmarksByCityLoading extends UserState {}

final class GetLandmarksByCitySuccess extends UserState {
  final List<Landmark> landmarks;
  GetLandmarksByCitySuccess({required this.landmarks});
}

final class GetLandmarksByCityFailure extends UserState {
  final String errMessage;
  GetLandmarksByCityFailure({required this.errMessage});
}

// ── Visits ────────────────────────────────────────────────────────────────
final class CreateVisitLoading extends UserState {}

final class CreateVisitSuccess extends UserState {
  final String message;
  CreateVisitSuccess({required this.message});
}

final class CreateVisitFailure extends UserState {
  final String errMessage;
  CreateVisitFailure({required this.errMessage});
}

// ── Profile ───────────────────────────────────────────────────────────────
final class GetProfileLoading extends UserState {}

final class GetProfileSuccess extends UserState {
  final String name;
  final String email;
  final String phoneNumber;
  final String country;
  final String role;
  final String imageUrl;

  GetProfileSuccess({
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.country,
    required this.role,
    this.imageUrl = '',
  });
}

final class GetProfileFailure extends UserState {
  final String errMessage;
  GetProfileFailure({required this.errMessage});
}

final class UserInfoUpdated extends UserState {}

// ── Chat ──────────────────────────────────────────────────────────────────
class ChatLoading extends UserState {}

class ChatSuccess extends UserState {
  final String answer;
  final double responseTimeSec;
  ChatSuccess({required this.answer, required this.responseTimeSec});
}

class ChatFailure extends UserState {
  final String errMessage;
  ChatFailure({required this.errMessage});
}

// ── Image ─────────────────────────────────────────────────────────────────
class UploadImageSuccess extends UserState {
  final String imageUrl;
  UploadImageSuccess({required this.imageUrl});
}