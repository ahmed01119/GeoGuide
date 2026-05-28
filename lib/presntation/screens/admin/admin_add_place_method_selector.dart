import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_colors.dart';

class AdminAddPlaceMethodSelector extends StatelessWidget {
  const AdminAddPlaceMethodSelector({
    super.key,
    required this.onManual,
    required this.onApi,
    required this.onAi,
  });

  final VoidCallback onManual;
  final VoidCallback onApi;
  final VoidCallback onAi;

  Widget _card({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color accent,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(color: accent.withOpacity(0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2E251F),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF8B817A),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.chestnutBrown,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF7F1EB),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.chestnutBrown.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.add_rounded, color: AppColors.chestnutBrown),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Place',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF2E251F),
                          fontSize: 18,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Choose a method',
                        style: TextStyle(
                          color: Color(0xFF8B817A),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _card(
              icon: Icons.edit_rounded,
              title: 'Manual Add',
              subtitle: 'Enter all place data manually.',
              onTap: onManual,
              accent: AppColors.chestnutBrown,
            ),
            const SizedBox(height: 12),
            _card(
              icon: Icons.cloud_download_rounded,
              title: 'Add using APIs',
              subtitle: 'Fetch place details/images from free public sources.',
              onTap: onApi,
              accent: const Color(0xFF6B8E23),
            ),
            const SizedBox(height: 12),
            _card(
              icon: Icons.auto_awesome_rounded,
              title: 'Add using AI',
              subtitle: 'Generate structured place data with AI, then review before saving.',
              onTap: onAi,
              accent: const Color(0xFF7B61FF),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

