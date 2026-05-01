// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_colors.dart';

class CustomTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? Function(String?) validator;
  final void Function(String) onChanged;
  final String hintText;
  final bool obscureText;
  final String? helperText;
  final TextStyle? helperStyle;
  final Widget? suffixIcon;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.validator,
    required this.onChanged,
    required this.hintText,
    this.obscureText = false,
    this.helperText,
    this.helperStyle,
    this.suffixIcon,
  });

  IconData _resolveIcon() {
    final text = hintText.toLowerCase();
    if (text.contains('name')) return Icons.person_rounded;
    if (text.contains('email')) return Icons.email_rounded;
    if (text.contains('confirm')) return Icons.lock_reset_rounded;
    if (text.contains('password')) return Icons.lock_rounded;
    return Icons.edit_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      onChanged: onChanged,
      cursorColor: AppColors.brown,
      style: const TextStyle(
        color: Color(0xFF2E251F),
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF8B817A),
          fontWeight: FontWeight.w500,
        ),
        errorStyle: const TextStyle(color: AppColors.red),
        helperText: helperText,
        helperStyle: helperStyle ??
            const TextStyle(
              color: Color(0xFF8B817A),
              fontSize: 12,
            ),
        prefixIcon: Icon(
          _resolveIcon(),
          color: const Color(0xFF8D6E63),
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF9F5F1),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFE8DDD1)),
          borderRadius: BorderRadius.circular(18),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(
            color: Color(0xFF8D6E63),
            width: 1.4,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.red),
          borderRadius: BorderRadius.circular(18),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: const BorderSide(
            color: AppColors.red,
            width: 1.4,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}