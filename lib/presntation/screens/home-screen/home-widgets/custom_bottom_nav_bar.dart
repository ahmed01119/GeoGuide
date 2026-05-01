import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/constants/app_text.dart';
import 'package:geoguide/cubit/user_cubit.dart';
import 'package:geoguide/presntation/screens/favorites-screen/favorites.dart';
import 'package:geoguide/presntation/screens/home-screen/home.dart';
import 'package:geoguide/presntation/screens/profile-screen/profile.dart';
import 'package:geoguide/presntation/screens/settings-screen/settings.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final VoidCallback? onHomeRefresh;

  const CustomBottomNavBar({
    super.key,
    this.currentIndex = 0,
    this.onHomeRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      elevation: 0,
      color: Colors.transparent,
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: AppColors.chestnutBrown,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: AppColors.chestnutBrown.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Home ─────────────────────────────────────────────────
            _buildNavItem(
              context,
              icon: Icons.home_rounded,
              label: AppText.home,
              isActive: currentIndex == 0,
              onTap: () {
                final navigator = Navigator.of(context);

                // Keep the exact same design.
                // If Home provides a refresh callback, run it immediately.
                if (onHomeRefresh != null) {
                  onHomeRefresh!();
                  return;
                }

                // Otherwise go back to Home as before.
                if (navigator.canPop()) {
                  navigator.popUntil(
                    (route) =>
                        route.settings.name == Home.routeName ||
                        route.isFirst,
                  );
                }
              },
            ),

            // ── Profile ───────────────────────────────────────────────
            _buildNavItem(
              context,
              icon: Icons.person_rounded,
              label: AppText.profile,
              isActive: currentIndex == 1,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BlocProvider.value(
                      value: context.read<UserCubit>(),
                      child: const Profile(),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(width: 44), // FAB notch space

            // ── Favorites ─────────────────────────────────────────────
            _buildNavItem(
              context,
              icon: Icons.favorite_rounded,
              label: AppText.favorites,
              isActive: currentIndex == 2,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const FavoritesPage()),
                );
              },
            ),

            // ── Settings ──────────────────────────────────────────────
            _buildNavItem(
              context,
              icon: Icons.settings_rounded,
              label: AppText.settings,
              isActive: currentIndex == 3,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BlocProvider.value(
                      value: context.read<UserCubit>(),
                      child: const Settings(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Center(
          child: SizedBox(
            height: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withOpacity(0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child:
                      Icon(icon, color: Colors.white, size: 21),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 11,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        height: 1,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}