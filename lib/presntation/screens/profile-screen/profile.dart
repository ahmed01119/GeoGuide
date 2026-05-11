import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/cubit/user-state.dart';
import 'package:geoguide/cubit/user_cubit.dart';
import 'package:geoguide/models.dart/user-model.dart';
import 'package:geoguide/presntation/screens/ai-image-details/saved_ai_images_page.dart';
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
            return SafeArea(
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
                            borderRadius: BorderRadius.circular(14),
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

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  expandedHeight: 280,
                  pinned: true,
                  stretch: true,
                  title: Center(
                    child: Text(
                                              'My Profile',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 25,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: .4,
                                              ),
                                            ),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: _GlassIconButton(
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
                    ),
                  ],
                  backgroundColor: AppColors.chestnutBrown,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(30),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  leading: Padding(
                    padding: const EdgeInsets.all(8),
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
                                  Colors.transparent,
                                  Colors.transparent,
                                  Colors.transparent,

                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 22,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.22),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    
                                    
                                    UserProfileHeader(
                                      user: user,
                                      imageUrl: state.imageUrl,
                                    ),

                                  ],
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
                    offset: const Offset(0, -1),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: themeBg,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(30),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
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
                              child: Column(
                                children: [
                                  UserStatsCard(
                                    icon: Icons.person_rounded,
                                    title: 'Name',
                                    value: user.name,
                                  ),
                                  UserStatsCard(
                                    icon: Icons.email_rounded,
                                    title: 'Email',
                                    value: user.email,
                                  ),
                                  UserStatsCard(
                                    icon: Icons.phone_rounded,
                                    title: 'Phone',
                                    value: user.phoneNumber.isNotEmpty
                                        ? user.phoneNumber
                                        : 'Not set',
                                  ),
                                  UserStatsCard(
                                    icon: Icons.flag_rounded,
                                    title: 'Country',
                                    value: user.country.isNotEmpty
                                        ? user.country
                                        : 'Not set',
                                  ),
                                  UserStatsCard(
                                    icon: Icons.verified_user_rounded,
                                    title: 'Role',
                                    value: user.role,
                                  ),
                                  UserStatsCard(
                                    icon: Icons.bookmark_rounded,
                                    title: 'Saved AI Images',
                                    value: 'View your saved results',
                                    trailingIcon:
                                        Icons.arrow_forward_ios_rounded,
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
                                ],
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
          }

          return SafeArea(
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
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withOpacity(0.20),
                ),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}