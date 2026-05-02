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
      body: SafeArea(
        child: BlocConsumer<UserCubit, UserState>(
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
              return const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF8D6E63),
                ),
              );
            }

            if (state is GetProfileFailure) {
              return Center(
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
              );
            }

            if (state is GetProfileSuccess) {
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
                  SliverToBoxAdapter(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                      decoration: BoxDecoration(
                        color: AppColors.chestnutBrown,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(34),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.chestnutBrown.withOpacity(0.22),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(50),
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.16),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.18),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Icon(
                                Icons.person_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'My Profile',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Manage your personal information and account settings.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 13.5,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          UserProfileHeader(
                            user: user,
                            imageUrl: state.imageUrl,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
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
                                  trailingIcon: Icons.arrow_forward_ios_rounded,
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
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: AppColors.chestnutBrown,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 56),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              onPressed: () {
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
                              icon: const Icon(Icons.edit_rounded),
                              label: const Text(
                                'Edit Profile',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF8D6E63),
              ),
            );
          },
        ),
      ),
    );
  }
}