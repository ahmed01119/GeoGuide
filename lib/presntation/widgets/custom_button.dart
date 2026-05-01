import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_colors.dart';

class CustomButton extends StatelessWidget {
  final GlobalKey<FormState>? formKey;
  final String title;
  final VoidCallback function;
  final IconData? icon;

  const CustomButton({
    super.key,
    required this.title,
    required this.function,
    required this.formKey,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.chestnutBrown,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        onPressed: () {
          if (formKey != null) {
            if (formKey!.currentState?.validate() == true) {
              function();
            }
          } else {
            function();
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 8),
              Icon(icon, size: 18, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}