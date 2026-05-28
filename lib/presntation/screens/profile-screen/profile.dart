import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/cubit/user-state.dart';
import 'package:geoguide/cubit/user_cubit.dart';
import 'package:geoguide/models.dart/user-model.dart';
import 'package:geoguide/presntation/screens/ai-image-details/saved_ai_images_page.dart';
import 'package:geoguide/presntation/screens/admin/admin_dashboard.dart';
import 'package:geoguide/presntation/screens/profile-screen/profile-widgets/user_profile_header.dart';
import 'package:geoguide/presntation/screens/profile-screen/profile-widgets/user_stats_card.dart';
import 'package:geoguide/presntation/screens/settings-screen/settings.dart';

class Profile extends StatefulWidget {
  static String routeName = '/profile';
  const Profile({super.key});

  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> {
  @override
  void initState() {
    super.initState();
    context.read<UserCubit>().getProfile();
  }

  double _horizontalPadding(double width) {
    if (width >= 1200) return 56;
    if (width >= 900) return 40;
    if (width >= 600) return 28;
    return 16;
  }

  double _appBarHeight(double width) {
    // Keep enough vertical space between the top controls and the glass card.
    // On small phones the old 280 height made the back/edit buttons visually
    // overlap the profile glass card.
    if (width >= 900) return 390;
    if (width >= 600) return 370;
    return 340;
  }

  double _statsCardWidth(double availableWidth) {
    if (availableWidth >= 1100) {
      return (availableWidth - 24) / 3;
    }

    if (availableWidth >= 700) {
      return (availableWidth - 12) / 2;
    }

    return availableWidth;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F1EB),
      body: BlocConsumer<UserCubit, UserState>(
        listenWhen: (prev, curr) => curr is UserInfoUpdated,
        listener: (context, state) {
          if (state is UserInfoUpdated) {
            context.read<UserCubit>().getProfile();
          }
        },
        buildWhen: (prev, curr) =>
            curr is GetProfileLoading ||
            curr is GetProfileSuccess ||
            curr is GetProfileFailure,
        builder: (context, state) {
          if (state is GetProfileLoading) {
            return const SafeArea(
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF8D6E63),
                ),
              ),
            );
          }

          if (state is GetProfileFailure) {
            return SafeArea(
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(24),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.redAccent,
                        size: 46,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        state.errMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF5E544D),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.chestnutBrown,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          context.read<UserCubit>().getProfile();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          if (state is GetProfileSuccess) {
            const themeBg = Color(0xFFF7F1EB);

            final user = UserModel(
              id: 0,
              name: state.name.isNotEmpty ? state.name : 'No Name',
              email: state.email.isNotEmpty ? state.email : 'No Email',
              phoneNumber: state.phoneNumber,
              country: state.country,
              role: state.role.isNotEmpty ? state.role : 'User',
              visits: 0,
              favorites: 0,
            );

            return LayoutBuilder(
              builder: (context, constraints) {
                final screenWidth = constraints.maxWidth;
                final pagePadding = _horizontalPadding(screenWidth);

                return CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverAppBar(
                      expandedHeight: _appBarHeight(screenWidth),
                      toolbarHeight: 76,
                      pinned: true,
                      stretch: true,
                      automaticallyImplyLeading: false,
                      backgroundColor: AppColors.chestnutBrown,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(30),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      flexibleSpace: LayoutBuilder(
                        builder: (context, appBarConstraints) {
                          final topInset = MediaQuery.of(context).padding.top;
                          final currentHeight = appBarConstraints.biggest.height;
                          final minVisibleHeight = topInset + 84;
                          final expandedEnough = currentHeight > minVisibleHeight;

                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppColors.chestnutBrown,
                                      AppColors.chestnutBrown,
                                    ],
                                  ),
                                ),
                              ),

                              // Top controls are placed in their own safe area
                              // layer, so they never sit on top of the profile
                              // glass card.
                              Positioned(
                                top: topInset + 10,
                                left: pagePadding,
                                right: pagePadding,
                                child: Row(
                                  children: [
                                    _GlassIconButton(
                                      icon: Icons.arrow_back_ios_new_rounded,
                                      onTap: () => Navigator.pop(context),
                                    ),
                                    const Expanded(
                                      child: Text(
                                        'My Profile',
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 25,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: .4,
                                        ),
                                      ),
                                    ),
                                    _GlassIconButton(
                                      icon: Icons.edit_rounded,
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

                              if (expandedEnough)
                                Positioned(
                                  left: pagePadding,
                                  right: pagePadding,
                                  bottom: 28,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(26),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                        sigmaX: 10,
                                        sigmaY: 10,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.14),
                                          borderRadius: BorderRadius.circular(26),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.22),
                                          ),
                                        ),
                                        child: UserProfileHeader(
                                          user: user,
                                          imageUrl: state.imageUrl,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Transform.translate(
                        offset: const Offset(0, -1),
                        child: Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: themeBg,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(30),
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              pagePadding,
                              18,
                              pagePadding,
                              30,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Personal Information',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF2E251F),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'View your saved account details.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF81756C),
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 16,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, cardConstraints) {
                                      final cardWidth = _statsCardWidth(
                                        cardConstraints.maxWidth,
                                      );

                                      return Wrap(
                                        spacing: 12,
                                        runSpacing: 12,
                                        children: [
                                          SizedBox(
                                            width: cardWidth,
                                            child: UserStatsCard(
                                              icon: Icons.person_rounded,
                                              title: 'Name',
                                              value: user.name,
                                            ),
                                          ),
                                          SizedBox(
                                            width: cardWidth,
                                            child: UserStatsCard(
                                              icon: Icons.email_rounded,
                                              title: 'Email',
                                              value: user.email,
                                            ),
                                          ),
                                          SizedBox(
                                            width: cardWidth,
                                            child: UserStatsCard(
                                              icon: Icons.phone_rounded,
                                              title: 'Phone',
                                              value: user.phoneNumber.isNotEmpty
                                                  ? user.phoneNumber
                                                  : 'Not set',
                                            ),
                                          ),
                                          SizedBox(
                                            width: cardWidth,
                                            child: UserStatsCard(
                                              icon: Icons.flag_rounded,
                                              title: 'Country',
                                              value: user.country.isNotEmpty
                                                  ? user.country
                                                  : 'Not set',
                                            ),
                                          ),
                                          SizedBox(
                                            width: cardWidth,
                                            child: UserStatsCard(
                                              icon:
                                                  Icons.verified_user_rounded,
                                              title: 'Role',
                                              value: user.role,
                                            ),
                                          ),
                                          SizedBox(
                                            width: cardWidth,
                                            child: UserStatsCard(
                                              icon: Icons.bookmark_rounded,
                                              title: 'Saved AI Images',
                                              value: 'View your saved results',
                                              trailingIcon: Icons
                                                  .arrow_forward_ios_rounded,
                                              onTap: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        const SavedAiImagesPage(),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          if (user.role.toLowerCase() == 'admin')
                                            SizedBox(
                                              width: cardWidth,
                                              child: UserStatsCard(
                                                icon: Icons.admin_panel_settings_rounded,
                                                title: 'Admin Panel',
                                                value: 'Open moderation and cleanup tools',
                                                trailingIcon: Icons.arrow_forward_ios_rounded,
                                                onTap: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          const AdminDashboard(),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 22),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          }

          return const SafeArea(
            child: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF8D6E63),
              ),
            ),
          );
        },
      ),
    );
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Material(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.20),
                ),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
