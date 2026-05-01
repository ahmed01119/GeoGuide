// ignore_for_file: sized_box_for_whitespace

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/constants/app_text.dart';
import 'package:geoguide/cubit/user-state.dart';
import 'package:geoguide/cubit/user_cubit.dart';
import 'package:geoguide/models.dart/login_model.dart';
import 'package:geoguide/presntation/screens/home-screen/home.dart';
import 'package:geoguide/presntation/screens/password_configuration/forgot_password.dart';
import 'package:geoguide/presntation/screens/signup-screen/signup.dart';
import 'package:geoguide/presntation/widgets/clickable-text.dart';
import 'package:geoguide/presntation/widgets/custom-scaffold.dart';
import 'package:geoguide/presntation/widgets/custom_button.dart';
import 'package:geoguide/presntation/widgets/sign-with.dart';
import 'package:geoguide/presntation/widgets/text-container.dart';

import 'login widget/login-form.dart';

class Login extends StatefulWidget {
  static String routeName = '/login';

  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
    final GlobalKey<FormState> _loginFormKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<UserCubit>();
    final size = MediaQuery.of(context).size;
    final height = size.height;
    final width = size.width;

    return SafeArea(
      child: BlocConsumer<UserCubit, UserState>(
        listener: (BuildContext context, state) {
          if (state is LoginInSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
              ),
            );
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BlocProvider.value(
                  value: BlocProvider.of<UserCubit>(context),
                  child: const Home(),
                ),
              ),
            );
          } else if (state is LoginInFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errMessage),
              ),
            );
          }
        },
        builder: (BuildContext context, state) {
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
                          text: AppText.loginTitle,
                          fontSize: 28,
                        ),
                        const SizedBox(height: 8),
                        TextContainer(
                          text: AppText.loginSubtitle,
                          fontSize: 18,
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
                child: Column(
                  children: [
                     LoginForm(formKey: _loginFormKey),

                    Container(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: 14,
                          bottom: 22,
                          right: 6,
                          left: 6,
                        ),
                        child: ClickableText(
                          title: AppText.forgotPassword,
                          textAlign: TextAlign.end,
                          size: 14,
                          color: AppColors.brownCinnamon,
                          fontWeight: FontWeight.w500,
                          function: () {
                            Navigator.pushNamed(
                              context,
                              ForgotPassword.routeName,
                            );
                          },
                        ),
                      ),
                    ),

                    state is LoginInLoading
                        ? const Center(child: CircularProgressIndicator())
                        : CustomButton(
                            title: AppText.signIn,
                            formKey: _loginFormKey,
                            icon: Icons.arrow_forward_rounded,
                            function: () {
                              if (_loginFormKey.currentState?.validate() ==
                                  true) {
                                final request = LoginRequest(
                                  email: cubit.logInEmail.text.trim(),
                                  password: cubit.logInPassword.text.trim(),
                                );

                                cubit.login(request);
                              }
                            },
                          ),
                  ],
                ),
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

              SizedBox(height: height * 0.02),

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
                child: SignWith(),
              ),

              SizedBox(height: height * 0.03),

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
                      AppText.needAnAccount,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF5E544D),
                      ),
                    ),
                    SizedBox(width: width * 0.01),
                    ClickableText(
                      title: AppText.registerNow,
                      size: 15,
                      color: AppColors.brown,
                      function: () {
                        Navigator.pushNamed(context, Signup.routeName);
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