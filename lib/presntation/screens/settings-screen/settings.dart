import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/constants/app_text.dart';
import 'package:geoguide/cubit/user_cubit.dart';
import 'package:geoguide/presntation/screens/settings-screen/settings-widgets/edit_name_dialog.dart';
import 'package:geoguide/presntation/screens/settings-screen/settings-widgets/settings_section.dart';

class Settings extends StatelessWidget {
  static String routeName = '/settings';

  const Settings({super.key});

  double _clampDouble(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<UserCubit>();
    const themeBg = Color(0xFFF7F1EB);

    final media = MediaQuery.of(context);
    final size = media.size;
    final width = size.width;
    final height = size.height;
    final shortest = size.shortestSide;

    final isTablet = shortest >= 600;

    final horizontalPadding = _clampDouble(width * 0.043, 14, 24);
    final contentPadding = _clampDouble(width * 0.043, 14, 22);
    final headerHeight = isTablet
        ? _clampDouble(height * 0.34, 310, 390)
        : _clampDouble(height * 0.31, 250, 320);

    final glassCardBottom = _clampDouble(height * 0.028, 22, 34);
    final titleFontSize = isTablet
        ? _clampDouble(width * 0.044, 28, 34)
        : _clampDouble(width * 0.064, 23, 28);
    final subtitleFontSize = isTablet
        ? _clampDouble(width * 0.021, 14, 16)
        : _clampDouble(width * 0.034, 12.5, 14);
    final badgeFontSize = isTablet
        ? _clampDouble(width * 0.018, 12, 14)
        : _clampDouble(width * 0.030, 11, 12.5);

    return Scaffold(
      backgroundColor: themeBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: headerHeight,
            pinned: true,
            stretch: true,
            toolbarHeight: 66,
            leadingWidth: 72,
            backgroundColor: AppColors.chestnutBrown,
            leading: Padding(
              padding: EdgeInsets.only(
                left: horizontalPadding,
                top: 5,
                bottom: 22,
              ),
              child: _GlassIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.pop(context),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.chestnutBrown,
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.16),
                            Colors.black.withOpacity(0.05),
                            Colors.black.withOpacity(0.42),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: horizontalPadding,
                    right: horizontalPadding,
                    bottom: glassCardBottom,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: EdgeInsets.all(contentPadding),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.22),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.10),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 360;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: _clampDouble(
                                        constraints.maxWidth * 0.035,
                                        10,
                                        14,
                                      ),
                                      vertical: _clampDouble(
                                        constraints.maxWidth * 0.018,
                                        6,
                                        8,
                                      ),
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.16),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'Preferences',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: badgeFontSize,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: .4,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    height: _clampDouble(height * 0.014, 9, 14),
                                  ),
                                  Text(
                                    compact
                                        ? 'Settings &\nprofile info'
                                        : 'Settings & profile info',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: titleFontSize,
                                      height: 1.12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(
                                    height: _clampDouble(height * 0.010, 6, 10),
                                  ),
                                  Text(
                                    'Manage your personal information and account details.',
                                    maxLines: compact ? 3 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.92),
                                      fontSize: subtitleFontSize,
                                      height: 1.45,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -10),
              child: Container(
                decoration: const BoxDecoration(
                  color: themeBg,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    _clampDouble(height * 0.015, 10, 16),
                    horizontalPadding,
                    _clampDouble(height * 0.032, 22, 34),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeader(
                        title: AppText.settings,
                        subtitle:
                            'Update your profile details and keep your information up to date.',
                      ),
                      SizedBox(height: _clampDouble(height * 0.020, 14, 20)),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(contentPadding),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: SettingsSection(
                          nameController: cubit.profileNameController,
                          onEditName: () =>
                              _editName(context, cubit.profileNameController),
                          phoneController: cubit.profilePhoneController,
                          countryController: cubit.profileCountryController,
                          emailController: cubit.profileEmailController,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _editName(
    BuildContext context,
    TextEditingController nameController,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<UserCubit>(),
        child: EditNameDialog(
          currentName: nameController.text,
        ),
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      nameController.text = result.trim();
    }
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final buttonSize = (width * 0.112).clamp(42.0, 50.0).toDouble();
    final radius = (width * 0.036).clamp(13.0, 16.0).toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Material(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: Colors.white.withOpacity(0.20),
                ),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: (buttonSize * 0.43).clamp(18.0, 22.0).toDouble(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  double _clampDouble(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;

    final titleSize = _clampDouble(width * 0.052, 18, 22);
    final subtitleSize = _clampDouble(width * 0.033, 12, 13.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2E251F),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: subtitleSize,
            color: const Color(0xFF81756C),
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
