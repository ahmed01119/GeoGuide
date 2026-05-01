import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'model_users.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Stream<User?> get userChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  bool get isGoogleUser {
    final user = _auth.currentUser;
    if (user == null) return false;

    return user.providerData.any(
      (info) => info.providerId == GoogleAuthProvider.PROVIDER_ID,
    );
  }

  bool get isEmailUser {
    final user = _auth.currentUser;
    if (user == null) return false;

    return user.providerData.any(
      (info) => info.providerId == EmailAuthProvider.PROVIDER_ID,
    );
  }

  Future<UserModel?> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final cleanName = name.trim();
      final cleanEmail = email.trim().toLowerCase();

      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) return null;

      await user.updateDisplayName(cleanName);
      await user.reload();

      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null) {
        throw Exception('Failed to create user.');
      }

      await refreshedUser.sendEmailVerification();

      final newUser = UserModel(
        uid: refreshedUser.uid,
        name: cleanName,
        email: refreshedUser.email ?? cleanEmail,
        image: refreshedUser.photoURL ?? '',
        favorites: [],
        createdAt: DateTime.now(),
      );

      await _firestore
          .collection('users')
          .doc(refreshedUser.uid)
          .set(newUser.toMap(), SetOptions(merge: true));

      // مهم: ما بنعملش signOut هنا
      // لأن VerifyEmailScreen الحالية معتمدة على currentUser
      return newUser;
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapFirebaseError(e));
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  Future<User?> login({
    required String email,
    required String password,
  }) async {
    try {
      final cleanEmail = email.trim().toLowerCase();

      final credential = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );

      final user = credential.user;
      if (user == null) return null;

      await user.reload();
      final refreshedUser = _auth.currentUser;

      if (refreshedUser == null) {
        throw Exception('Login failed. Please try again.');
      }

      if (!refreshedUser.emailVerified) {
        await _auth.signOut();
        throw Exception(
          'Please verify your email before signing in. Check your inbox or resend the verification email.',
        );
      }

      return refreshedUser;
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapFirebaseError(e));
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> forgetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(
        email: email.trim().toLowerCase(),
      );
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapFirebaseError(e));
    } catch (e) {
      throw Exception('Failed to send reset email: $e');
    }
  }

  Future<void> resendVerificationEmail() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No signed-in user found.');
      }

      await user.reload();
      final refreshedUser = _auth.currentUser;

      if (refreshedUser == null) {
        throw Exception('No signed-in user found.');
      }

      if (refreshedUser.emailVerified) {
        throw Exception('Email is already verified.');
      }

      await refreshedUser.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapFirebaseError(e));
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('Not signed in.');
    }

    if (!isEmailUser) {
      throw Exception(
        'Your password is managed by Google. Please change it from your Google Account settings.',
      );
    }

    final email = user.email;
    if (email == null || email.trim().isEmpty) {
      throw Exception('No email found for the current user.');
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );

    try {
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapFirebaseError(e));
    } catch (e) {
      throw Exception('Failed to change password: $e');
    }
  }

  Future<UserModel?> signInWithGoogle() async {
    try {
      await _googleSignIn.signOut();

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (!doc.exists) {
        final newUser = UserModel(
          uid: user.uid,
          name: user.displayName ?? '',
          email: user.email ?? '',
          image: user.photoURL ?? '',
          favorites: [],
          createdAt: DateTime.now(),
        );

        await _firestore
            .collection('users')
            .doc(user.uid)
            .set(newUser.toMap(), SetOptions(merge: true));

        return newUser;
      }

      return UserModel.fromDocument(doc);
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapFirebaseError(e));
    } catch (e) {
      throw Exception('Google sign-in failed: $e');
    }
  }

  Future<void> logout() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<UserModel?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();

      if (doc.exists) {
        return UserModel.fromDocument(doc);
      }

      return null;
    } catch (e) {
      throw Exception('Failed to get user data: $e');
    }
  }

  String _mapFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      default:
        return e.message ?? 'An error occurred. Please try again.';
    }
  }
}