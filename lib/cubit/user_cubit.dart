import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geoguide/models.dart/landmark_model.dart';
import 'package:geoguide/models.dart/login_model.dart';
import 'package:geoguide/presntation/screens/signup-screen/signup-widget/signup-form.dart';
import 'package:geoguide/services/auth_service.dart';
import 'package:geoguide/services/chatbot_service.dart';
import 'package:geoguide/services/cloudinary_service.dart';
import 'package:geoguide/services/firebase_service.dart';
import 'package:geoguide/cubit/user-state.dart';
import 'package:image_picker/image_picker.dart';

// ignore: depend_on_referenced_packages
class UserCubit extends Cubit<UserState> {
  final FirebaseService firebaseService = FirebaseService();
  final AuthService authService;
final ChatbotService chatbotService = ChatbotService();
  UserCubit(this.authService) : super(UserInitial());

  final picker = ImagePicker();
  bool _isGoogleSigningIn = false;

  // ── Text Controllers ──────────────────────────────────────────────────────
  final TextEditingController logInEmail = TextEditingController();
  final TextEditingController logInPassword = TextEditingController();

  final TextEditingController signUpName = TextEditingController();
  final TextEditingController signUpEmail = TextEditingController();
  final TextEditingController signUpPassword = TextEditingController();
  final TextEditingController signUpConfirmPassword = TextEditingController();

  final TextEditingController profileNameController = TextEditingController();
  final TextEditingController profileEmailController = TextEditingController();
  final TextEditingController profilePhoneController = TextEditingController();
  final TextEditingController profileCountryController = TextEditingController();
  final TextEditingController profileRoleController = TextEditingController();

  bool get isGoogleUser => authService.isGoogleUser;
  bool get isEmailUser => authService.isEmailUser;
  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  // ── Auth ──────────────────────────────────────────────────────────────────
  Future<void> login(LoginRequest request) async {
    emit(LoginInLoading());
    try {
      await authService.login(
        email: request.email,
        password: request.password,
      );
      emit(LoginInSuccess(message: 'Login successful'));
    } catch (e) {
      emit(
        LoginInFailure(
          errMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  Future<void> signUp(SignUpRequest request) async {
    emit(SignUpLoading());
    try {
      final user = await authService.register(
        name: request.name,
        email: request.email,
        password: request.password,
      );
      if (user != null) {
        emit(SignUpSuccess(message: 'Account created successfully'));
      } else {
        emit(SignUpFailure(errMessage: 'Failed to create account'));
      }
    } catch (e) {
      emit(
        SignUpFailure(
          errMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  Future<void> forgetPassword(String email) async {
    emit(ForgetPasswordLoading());
    try {
      await authService.forgetPassword(email);
      emit(ForgetPasswordSuccess(message: 'Reset email sent'));
    } catch (e) {
      emit(
        ForgetPasswordFailure(
          errMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    emit(ChangePasswordLoading());
    try {
      await authService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      emit(ChangePasswordSuccess(message: 'Password changed successfully'));
    } catch (e) {
      emit(
        ChangePasswordFailure(
          errMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  Future<void> googleSignIn() async {
    if (_isGoogleSigningIn) return;
    _isGoogleSigningIn = true;
    emit(LoginInLoading());

    try {
      final user = await authService.signInWithGoogle();
      if (user != null) {
        emit(LoginInSuccess(message: 'Google SignIn successful'));
      } else {
        emit(LoginInFailure(errMessage: 'Google SignIn cancelled'));
      }
    } catch (e) {
      emit(
        LoginInFailure(
          errMessage: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    } finally {
      _isGoogleSigningIn = false;
    }
  }

  Future<void> logout() async {
    await authService.logout();
    logInEmail.clear();
    logInPassword.clear();
    signUpName.clear();
    signUpEmail.clear();
    signUpPassword.clear();
    signUpConfirmPassword.clear();
    profileNameController.clear();
    profileEmailController.clear();
    profilePhoneController.clear();
    profileCountryController.clear();
    profileRoleController.clear();
    emit(UserInitial());
  }

  // ── Cities ────────────────────────────────────────────────────────────────
  Future<void> getAllCities() async {
    emit(GetAllCitiesLoading());
    try {
      final cities = await firebaseService.getCities();
      emit(GetAllCitiesSuccess(cities: cities));
    } catch (e) {
      emit(GetAllCitiesFailure(errMessage: 'Failed to load cities: $e'));
    }
  }

  // ── Landmarks ─────────────────────────────────────────────────────────────
  Future<void> getLandmarksByCity(String cityId) async {
    emit(GetLandmarksByCityLoading());
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('landmarks')
          .where('cityId', isEqualTo: cityId)
          .get();

      final landmarks = snapshot.docs
          .map((doc) => Landmark.fromJson(doc.data(), doc.id))
          .toList();

      emit(GetLandmarksByCitySuccess(landmarks: landmarks));
    } catch (e) {
      emit(
        GetLandmarksByCityFailure(
          errMessage: 'Failed to load landmarks: $e',
        ),
      );
    }
  }

  Future<void> getAllLandmarks() async {
    emit(GetAllLandmarksLoading());
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('landmarks').get();

      final landmarks = snapshot.docs
          .map((doc) => Landmark.fromJson(doc.data(), doc.id))
          .toList();

      emit(GetAllLandmarksSuccess(landmarks: landmarks));
    } catch (e) {
      emit(GetAllLandmarksFailure(errMessage: 'Failed to load landmarks'));
    }
  }

  Future<void> getPlacesByCity({
    required String city,
    String? category,
  }) async {
    emit(GetPlacesLoading());
    try {
      Query query = FirebaseFirestore.instance
          .collection('landmarks')
          .where('city', isEqualTo: city);

      if (category != null && category.trim().isNotEmpty) {
        query = query.where('category', isEqualTo: category);
      }

      final snapshot = await query.get();

      final places = snapshot.docs
          .map(
            (doc) =>
                Landmark.fromJson(doc.data() as Map<String, dynamic>, doc.id),
          )
          .toList();

      emit(GetPlacesSuccess(places));
    } catch (e) {
      emit(GetPlacesFailure(e.toString()));
    }
  }

  // ── Visits ────────────────────────────────────────────────────────────────
  Future<void> createVisit({
    required String userId,
    required String landmarkId,
    required DateTime date,
  }) async {
    emit(CreateVisitLoading());
    try {
      await FirebaseFirestore.instance.collection('visits').add({
        'userId': userId,
        'landmarkId': landmarkId,
        'date': date.toIso8601String(),
      });
      emit(CreateVisitSuccess(message: 'Visit recorded successfully'));
    } catch (e) {
      emit(CreateVisitFailure(errMessage: 'Failed to record visit'));
    }
  }

  // ── Profile ───────────────────────────────────────────────────────────────
  Future<void> getProfile() async {
    final uid = currentUid;
    if (uid == null) {
      emit(GetProfileFailure(errMessage: 'Not signed in'));
      return;
    }

    emit(GetProfileLoading());

    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();

      if (data == null) {
        final authUser = FirebaseAuth.instance.currentUser;
        if (authUser != null) {
          final name = authUser.displayName ?? '';
          final email = authUser.email ?? '';

          profileNameController.text = name;
          profileEmailController.text = email;
          profilePhoneController.text = '';
          profileCountryController.text = '';
          profileRoleController.text = 'User';

          emit(
            GetProfileSuccess(
              name: name,
              email: email,
              phoneNumber: '',
              country: '',
              role: 'User',
              imageUrl: authUser.photoURL ?? '',
            ),
          );
          return;
        }

        emit(GetProfileFailure(errMessage: 'No profile found'));
        return;
      }

      profileNameController.text = (data['name'] ?? '').toString();
      profileEmailController.text = (data['email'] ?? '').toString();
      profilePhoneController.text = (data['phone'] ?? '').toString();
      profileCountryController.text = (data['country'] ?? '').toString();
      profileRoleController.text = (data['role'] ?? 'User').toString();

      emit(
        GetProfileSuccess(
          name: (data['name'] ?? '').toString(),
          email: (data['email'] ?? '').toString(),
          phoneNumber: (data['phone'] ?? '').toString(),
          country: (data['country'] ?? '').toString(),
          role: (data['role'] ?? 'User').toString(),
          imageUrl: (data['image'] ?? '').toString(),
        ),
      );
    } catch (e) {
      emit(GetProfileFailure(errMessage: 'Failed to load profile'));
    }
  }

Future<bool> updateProfileImageCloudinary(XFile imageFile) async {
  final uid = currentUid;

  if (uid == null) {
    emit(GetProfileFailure(errMessage: 'User not logged in'));
    return false;
  }

  try {
    final imageUrl = await CloudinaryService.uploadProfileImage(imageFile);

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'image': imageUrl,
    }, SetOptions(merge: true));

    emit(UserInfoUpdated());
    return true;
  } catch (e) {
    debugPrint('Cloudinary profile image error: $e');
    emit(GetProfileFailure(errMessage: 'Failed to upload profile image'));
    return false;
  }
}

  void updateUserInfo({
    String? name,
    String? phone,
    String? country,
  }) {
    if (name != null) profileNameController.text = name;
    if (phone != null) profilePhoneController.text = phone;
    if (country != null) profileCountryController.text = country;
    emit(UserInfoUpdated());
  }

  Future<bool> updateUserInfoFirebase({
    String? name,
    String? phone,
    String? country,
  }) async {
    final uid = currentUid;
    if (uid == null) {
      emit(GetProfileFailure(errMessage: 'User not logged in'));
      return false;
    }

    try {
      final updateData = <String, dynamic>{};

      if (name != null && name.trim().isNotEmpty) {
        final clean = name.trim();
        profileNameController.text = clean;
        updateData['name'] = clean;
      }

      if (phone != null) {
        final clean = phone.trim();
        profilePhoneController.text = clean;
        updateData['phone'] = clean;
      }

      if (country != null && country.trim().isNotEmpty) {
        final clean = country.trim();
        profileCountryController.text = clean;
        updateData['country'] = clean;
      }

      if (updateData.isEmpty) return false;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(updateData, SetOptions(merge: true));

      emit(UserInfoUpdated());
      return true;
    } catch (e) {
      debugPrint('Error updating user info: $e');
      emit(GetProfileFailure(errMessage: 'Failed to update profile'));
      return false;
    }
  }

  // ── Chat ─────────────────────────────────────────────────────────────────
  /// [lang] is optional for backward-compat with chatbot.dart call: sendChat(text, "en")
 Future<void> sendChat(String message, [String lang = 'en']) async {
  final clean = message.trim();
  if (clean.isEmpty) return;

  emit(ChatLoading());

  try {
    final result = await chatbotService.ask(clean);

    debugPrint('[Chatbot] source: ${result.source}');
    debugPrint('[Chatbot] response time: ${result.responseTimeSec}');
    debugPrint('[Chatbot] answer: ${result.answer}');

    if (result.source == ChatbotSource.error) {
      emit(
        ChatFailure(
          errMessage: result.answer,
        ),
      );
      return;
    }

    emit(
      ChatSuccess(
        answer: result.answer,
        responseTimeSec: result.responseTimeSec,
      ),
    );
  } catch (e) {
    debugPrint('[Chatbot ERROR] $e');

    emit(
      ChatFailure(
        errMessage: 'Chat error: $e',
      ),
    );
  }
}


  @override
  Future<void> close() {
    logInEmail.dispose();
    logInPassword.dispose();

    signUpName.dispose();
    signUpEmail.dispose();
    signUpPassword.dispose();
    signUpConfirmPassword.dispose();

    profileNameController.dispose();
    profileEmailController.dispose();
    profilePhoneController.dispose();
    profileCountryController.dispose();
    profileRoleController.dispose();

    return super.close();
  }
}