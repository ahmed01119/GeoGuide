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
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 10,
        elevation: 0,
        color: AppColors.chestnutBrown,
        surfaceTintColor: Colors.transparent,
        child: SizedBox(
          height: 76,
          child: Row(
            children: [
              _buildNavItem(
                context,
                icon: Icons.home_rounded,
                label: AppText.home,
                isActive: currentIndex == 0,
                onTap: () {},
              ),
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
              const SizedBox(width: 56),
              _buildNavItem(
                context,
                icon: Icons.star_border_rounded,
                label: AppText.favorites,
                isActive: currentIndex == 2,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FavoritesPage(),
                    ),
                  );
                },
              ),
              _buildNavItem(
                context,
                icon: Icons.settings_rounded,
                label: AppText.settings,
                isActive: currentIndex == 3,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const Settings(),
                    ),
                  );
                },
              ),
            ],
          ),
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
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withOpacity(0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child:
                      Icon(icon, color: Colors.white, size: 29),
                ),
                const SizedBox(height: 1),
                SizedBox(
                  height: 16,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        height: 1,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w600,
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