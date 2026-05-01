// ignore_for_file: unused_local_variable

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/constants/app_text.dart';
import 'package:geoguide/cubit/user-state.dart';
import 'package:geoguide/cubit/user_cubit.dart';
import 'package:geoguide/presntation/screens/login%20screen/login.dart';
import 'package:geoguide/presntation/screens/signup-screen/signup-widget/signup-form.dart';
import 'package:geoguide/presntation/screens/signup-screen/verify_email_screen.dart';
import 'package:geoguide/presntation/widgets/clickable-text.dart';
import 'package:geoguide/presntation/widgets/custom-scaffold.dart';
import 'package:geoguide/presntation/widgets/sign-with.dart';
import 'package:geoguide/presntation/widgets/text-container.dart';

class Signup extends StatefulWidget {
  static String routeName = '/signup';

  const Signup({super.key});

  @override
  State<Signup> createState() => _SignupState();
}

class _SignupState extends State<Signup> {
  final GlobalKey<FormState> _signUpFormKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final height = size.height;

    return SafeArea(
      child: BlocConsumer<UserCubit, UserState>(
        listener: (BuildContext context, UserState state) {
          if (state is SignUpSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Account created successfully. Please verify your email before signing in.',
                ),
                backgroundColor: Colors.green,
              ),
            );

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const VerifyEmailScreen(),
              ),
            );
          } else if (state is SignUpFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errMessage),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        builder: (BuildContext context, Object? state) {
          return CustomScaffold(
            children: [
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextContainer(
                          text: AppText.signup,
                          fontSize: 28,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Create your account and start exploring places across Egypt.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: height * 0.03),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: SignUpForm(formKey: _signUpFormKey),
              ),
              SizedBox(height: height * 0.025),
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: AppColors.brown.withOpacity(0.4),
                      thickness: 0.7,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or continue with',
                      style: TextStyle(
                        color: Color(0xFF7E746C),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: AppColors.brown.withOpacity(0.4),
                      thickness: 0.7,
                    ),
                  ),
                ],
              ),
              SizedBox(height: height * 0.018),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const SignWith(),
              ),
              SizedBox(height: height * 0.025),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      AppText.alreadyAMember,
                      style: const TextStyle(
                        color: Color(0xFF5E544D),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 5),
                    ClickableText(
                      title: AppText.signIn,
                      size: 14,
                      color: AppColors.brown,
                      function: () {
                        Navigator.pushReplacementNamed(
                          context,
                          Login.routeName,
                        );
                      },
                      fontWeight: FontWeight.bold,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}