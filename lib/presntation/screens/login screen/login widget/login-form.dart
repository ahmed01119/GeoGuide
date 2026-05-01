// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geoguide/constants/app_colors.dart';
import '../../../../cubit/user_cubit.dart';

class LoginForm extends StatefulWidget {
    final GlobalKey<FormState> formKey;

  const LoginForm({
    super.key,    required this.formKey,

  });

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  bool isVisible = false;

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    } else if (!value.contains('@')) {
      return 'Enter a valid email';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    } else if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: Color(0xFF8B817A),
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(
        icon,
        color: const Color(0xFF8D6E63),
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF9F5F1),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 18,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color(0xFFE8DDD1),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color(0xFFE8DDD1),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color(0xFF8D6E63),
          width: 1.4,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Colors.redAccent,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Colors.redAccent,
          width: 1.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<UserCubit>();

    return Form(
      key: widget.formKey,
      child: Column(
        children: [
          TextFormField(
            controller: cubit.logInEmail,
            validator: _validateEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: _decoration(
              label: 'Email',
              icon: Icons.email_rounded,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: cubit.logInPassword,
            validator: _validatePassword,
            obscureText: !isVisible,
            decoration: _decoration(
              label: 'Password',
              icon: Icons.lock_rounded,
              suffixIcon: IconButton(
                icon: Icon(
                  isVisible
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: const Color(0xFF8D6E63),
                ),
                onPressed: () {
                  setState(() {
                    isVisible = !isVisible;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}