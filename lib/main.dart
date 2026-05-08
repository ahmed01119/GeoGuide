import 'package:cloud_firestore/cloud_firestore.dart' hide Settings;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:geoguide/cache/cache-helper.dart';
import 'package:geoguide/constants/app_injector.dart';
import 'package:geoguide/cubit/user_cubit.dart';
import 'package:geoguide/firebase_options.dart';
import 'package:geoguide/presntation/createcity.dart';
import 'package:geoguide/presntation/screens/home-screen/home.dart';
import 'package:geoguide/presntation/screens/login%20screen/login.dart';
import 'package:geoguide/presntation/screens/onboarding.dart';
import 'package:geoguide/presntation/screens/password_configuration/forgot_password.dart';
import 'package:geoguide/presntation/screens/password_configuration/reset_password.dart';
import 'package:geoguide/presntation/screens/profile-screen/profile.dart';
import 'package:geoguide/presntation/screens/settings-screen/settings.dart';
import 'package:geoguide/presntation/screens/signup-screen/signup.dart';
import 'package:geoguide/presntation/screens/signup-screen/verify_email_screen.dart';
import 'package:geoguide/services/auth_service.dart';
import 'package:geoguide/utils/city_seader.dart';

Future<void> clearBadImageLinksFromFirestore() async {
  final snapshot = await FirebaseFirestore.instance.collection('landmarks').get();

  for (final doc in snapshot.docs) {
    final data = doc.data();

    final imageUrl = (data['imageUrl'] ?? '').toString();
    final mediaUrls = List<String>.from(data['mediaUrls'] ?? []);

    final hasBadMain = imageUrl.contains('loremflickr.com');

    final cleanedMedia = mediaUrls
        .where((u) => !u.toString().contains('loremflickr.com'))
        .toList();

    await doc.reference.update({
      if (hasBadMain) 'imageUrl': FieldValue.delete(),
      'mediaUrls': cleanedMedia,
      'imagesRefreshedAt': FieldValue.delete(),
    });
  }

  debugPrint('Bad loremflickr links removed ✅');
}

Future<void> clearImagesFromFirestore() async {
  final snapshot = await FirebaseFirestore.instance.collection('landmarks').get();

  for (final doc in snapshot.docs) {
    await doc.reference.update({
      'imageUrl': FieldValue.delete(),
      'mediaUrls': FieldValue.delete(),
      'imagesRefreshedAt': FieldValue.delete(),
    });
  }

  debugPrint('Images + refresh timestamps cleared safely ✅');
}

Future<void> keepOnlyTenLandmarks() async {
  try {
    final firestore = FirebaseFirestore.instance;

    final snapshot = await firestore.collection('landmarks').get();

    print('Total landmarks: ${snapshot.docs.length}');

    if (snapshot.docs.length <= 10) {
      print('Already 10 or less.');
      return;
    }

    final batch = firestore.batch();

    // سيب أول 10 وامسح الباقي
    for (int i = 10; i < snapshot.docs.length; i++) {
      final doc = snapshot.docs[i];

      print('Deleting: ${doc.id}');

      batch.delete(doc.reference);
    }

    await batch.commit();

    print('Deleted successfully.');
  } catch (e) {
    print('ERROR: $e');
  }
}

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }

  await CacheHelper.init();

  final isSeeded = await CacheHelper.getData(key: 'seeded') ?? false;

  if (!isSeeded) {
    await CitySeeder.seedIfEmpty();
    await CacheHelper.saveData(key: 'seeded', value: true);
  }
  FlutterNativeSplash.remove();
await clearBadImageLinksFromFirestore();
await clearImagesFromFirestore();
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => UserCubit(AuthService())),
        BlocProvider(create: (_) => AppInjector.buildPlacesCubit()),
      ],
      child: const GeoGuideApp(),
    ),
  );
}

class GeoGuideApp extends StatelessWidget {
  const GeoGuideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: Onboarding.routeName,
      routes: {
        Onboarding.routeName: (_) => const Onboarding(),
        Login.routeName: (_) => Login(),
        Home.routeName: (_) => const Home(),
        Signup.routeName: (_) => Signup(),
        ForgotPassword.routeName: (_) => ForgotPassword(),
        ResetPassword.routeName: (_) => ResetPassword(),
        Profile.routeName: (_) => const Profile(),
        Settings.routeName: (_) => const Settings(),
        CreateCity.routeName: (_) => const CreateCity(),
        VerifyEmailScreen.routeName: (_) => const VerifyEmailScreen(),
      },
    );
  }
}