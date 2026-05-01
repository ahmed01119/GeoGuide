// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/constants/app_text.dart';
import 'package:geoguide/cubit/user_cubit.dart';
import 'package:geoguide/presntation/widgets/custom-text-field.dart';
import 'package:geoguide/presntation/widgets/custom_button.dart';

class SignUpRequest {
  final String name;
  final String email;
  final String password;

  SignUpRequest({
    required this.name,
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'password': password,
    };
  }
}

class SignUpForm extends StatefulWidget {
  final GlobalKey<FormState> formKey;

  const SignUpForm({
    super.key,
    required this.formKey,
  });

  @override
  State<SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<SignUpForm> {
  bool isPasswordVisible = false;
  bool isConfirmPasswordVisible = false;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<UserCubit>();

    return Form(
      key: widget.formKey,
      child: Column(
        children: [
          CustomTextField(
            controller: cubit.signUpName,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return AppText.required;
              }
              if (!RegExp(r'^[A-Za-z]+( [A-Za-z]+)*$').hasMatch(value.trim())) {
                return AppText.notValid;
              }
              return null;
            },
            onChanged: (_) {},
            hintText: AppText.name,
          ),
          const SizedBox(height: 15),
          CustomTextField(
            controller: cubit.signUpEmail,
            validator: (value) {
              final email = value?.trim() ?? '';

              if (email.isEmpty) {
                return AppText.emailValidator1;
              }

              final emailRegex = RegExp(
                r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
              );

              if (!emailRegex.hasMatch(email)) {
                return AppText.emailValidator2;
              }

              return null;
            },
            onChanged: (value) {
              final cleaned = value.trim().toLowerCase();
              if (cleaned != cubit.signUpEmail.text) {
                cubit.signUpEmail.value = TextEditingValue(
                  text: cleaned,
                  selection: TextSelection.collapsed(offset: cleaned.length),
                );
              }
            },
            hintText: AppText.email,
          ),
          const SizedBox(height: 15),
          CustomTextField(
            controller: cubit.signUpPassword,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AppText.enterPassword;
              }
              if (value.length < 8 || value.length > 20) {
                return AppText.passwordValidator3;
              }
              if (!RegExp(r'[A-Z]').hasMatch(value)) {
                return AppText.passwordValidation1;
              }
              if (!RegExp(r'[a-z]').hasMatch(value)) {
                return AppText.passwordValidation2;
              }
              if (!RegExp(r'[0-9]').hasMatch(value)) {
                return AppText.passwordValidation3;
              }
              if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(value)) {
                return AppText.passwordValidation4;
              }
              return null;
            },
            onChanged: (_) {},
            hintText: AppText.password,
            obscureText: !isPasswordVisible,
            helperText: AppText.passwordHintText,
            helperStyle: const TextStyle(color: AppColors.hintText),
            suffixIcon: IconButton(
              onPressed: () {
                setState(() {
                  isPasswordVisible = !isPasswordVisible;
                });
              },
              icon: Icon(
                isPasswordVisible
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: const Color(0xFF8D6E63),
              ),
            ),
          ),
          const SizedBox(height: 15),
          CustomTextField(
            controller: cubit.signUpConfirmPassword,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AppText.enterPassword;
              }
              if (value != cubit.signUpPassword.text) {
                return AppText.passwordsDoNotMatch;
              }
              return null;
            },
            onChanged: (_) {},
            hintText: AppText.confirmPassword,
            obscureText: !isConfirmPasswordVisible,
            suffixIcon: IconButton(
              onPressed: () {
                setState(() {
                  isConfirmPasswordVisible = !isConfirmPasswordVisible;
                });
              },
              icon: Icon(
                isConfirmPasswordVisible
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: const Color(0xFF8D6E63),
              ),
            ),
          ),
          const SizedBox(height: 20),
          CustomButton(
            title: AppText.signup,
            formKey: widget.formKey,
            icon: Icons.arrow_forward_rounded,
            function: () {
              if (widget.formKey.currentState?.validate() == true) {
                final request = SignUpRequest(
                  name: cubit.signUpName.text.trim(),
                  email: cubit.signUpEmail.text.trim(),
                  password: cubit.signUpPassword.text.trim(),
                );

                cubit.signUp(request);
              }
            },
          ),
        ],
      ),
    );
  }
}