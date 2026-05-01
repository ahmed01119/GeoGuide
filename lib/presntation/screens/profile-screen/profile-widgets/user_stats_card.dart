import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_colors.dart';

class UserStatsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final IconData? trailingIcon;
  final VoidCallback? onTap;

  const UserStatsCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.trailingIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF9F6), // نفس خلفية الكروت في الأب
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE6DED6),
        ),
      ),
      child: Row(
        children: [
          /// Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.chestnutBrown.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: AppColors.chestnutBrown,
              size: 20,
            ),
          ),

          const SizedBox(width: 12),

          /// Title + Value
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8B817A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2E251F),
                  ),
                ),
              ],
            ),
          ),

          /// Trailing
          if (trailingIcon != null)
            InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.chestnutBrown.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  trailingIcon,
                  color: AppColors.chestnutBrown,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }
}