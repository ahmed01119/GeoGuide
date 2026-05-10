import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/constants/app_text.dart';
import 'package:geoguide/cubit/user_cubit.dart';
import 'package:geoguide/presntation/screens/login%20screen/login.dart';
import 'package:geoguide/presntation/screens/password_configuration/reset_password.dart';
import 'package:geoguide/presntation/screens/settings-screen/settings-widgets/edit_name_dialog.dart';
import 'package:geoguide/presntation/screens/settings-screen/settings-widgets/edit_phone_dialog.dart';

class SettingsSection extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController emailController;
  final VoidCallback onEditName;
  final TextEditingController phoneController;
  final TextEditingController countryController;

  const SettingsSection({
    super.key,
    required this.nameController,
    required this.onEditName,
    required this.phoneController,
    required this.countryController,
    required this.emailController,
  });

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection> {
  bool _showCountryOptions = false;

  final List<String> _countries = [
    'Egypt',
    'France',
    'United States',
    'Germany',
    'Italy',
    'United Kingdom',
    'Spain',
    'Canada',
    'Brazil',
    'Saudi Arabia',
    'UAE',
    'Turkey',
    'Japan',
    'China',
    'India',
  ];

  String get _currentEmail => FirebaseAuth.instance.currentUser?.email ?? '';

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<UserCubit>();
    final isGoogle = cubit.isGoogleUser;

    return Column(
      children: [
        // ── Name ───────────────────────────────────────────────────────
        _buildCard(
          icon: Icons.person_rounded,
          title: AppText.username,
          value: widget.nameController.text.isEmpty
              ? 'No name'
              : widget.nameController.text,
          onTap: () async {
            final result = await showDialog<String>(
              context: context,
              builder: (_) => BlocProvider.value(
                value: context.read<UserCubit>(),
                child: EditNameDialog(
                  currentName: widget.nameController.text,
                ),
              ),
            );

            if (result != null && result.trim().isNotEmpty) {
              setState(() {
                widget.nameController.text = result.trim();
              });
            }
          },
          isEditable: true,
        ),

        // ── Email (read-only) ──────────────────────────────────────────
        _buildCard(
          icon: Icons.email_rounded,
          title: AppText.email,
          value: _currentEmail.isNotEmpty ? _currentEmail : 'Not available',
        ),

        // ── Password (smart based on auth provider) ────────────────────
        if (isGoogle)
          _buildCard(
            icon: Icons.lock_outline_rounded,
            title: AppText.changePassword,
            value: 'Managed by Google',
            onTap: () => _showGooglePasswordDialog(context),
            trailingIcon: Icons.info_outline_rounded,
          )
        else
          _buildCard(
            icon: Icons.lock_rounded,
            title: AppText.changePassword,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BlocProvider.value(
                    value: cubit,
                    child: const ResetPassword(needCurrentPassword: true),
                  ),
                ),
              );
            },
            showArrow: true,
          ),

        // ── Phone ──────────────────────────────────────────────────────
        _buildCard(
          icon: Icons.phone_rounded,
          title: AppText.phone,
          value: widget.phoneController.text.isEmpty
              ? AppText.addNumber
              : widget.phoneController.text,
          onTap: () async {
            final result = await showDialog<String>(
              context: context,
              builder: (_) => BlocProvider.value(
                value: cubit,
                child: EditPhoneDialog(
                  currentPhone: widget.phoneController.text,
                ),
              ),
            );

            if (result != null && result.trim().isNotEmpty) {
              setState(() {
                widget.phoneController.text = result.trim();
              });
            }
          },
          isEditable: true,
        ),

        // ── Country ────────────────────────────────────────────────────
        _buildCard(
          icon: Icons.flag_rounded,
          title: AppText.country,
          value: widget.countryController.text.isEmpty
              ? AppText.selectCountry
              : widget.countryController.text,
          onTap: () =>
              setState(() => _showCountryOptions = !_showCountryOptions),
          trailingIcon: _showCountryOptions
              ? Icons.keyboard_arrow_up
              : Icons.keyboard_arrow_down,
        ),

        if (_showCountryOptions) _buildCountryList(context),

        // ── Logout ─────────────────────────────────────────────────────
        _buildCard(
          icon: Icons.logout_rounded,
          title: AppText.logout,
          onTap: () => _confirmLogout(context, cubit),
          isDanger: true,
        ),
      ],
    );
  }

  // ── Google password info dialog ───────────────────────────────────────────
  void _showGooglePasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFF8D6E63)),
            SizedBox(width: 8),
            Text('Google Account',
                style: TextStyle(
                    color: Color(0xFF2E251F), fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Text(
          'Your account uses Google Sign-In. Your password is '
          'managed by Google.\n\n'
          'To change your password, please visit your Google '
          'Account settings at myaccount.google.com.',
          style: TextStyle(color: Color(0xFF5E544D), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFF8D6E63))),
          ),
        ],
      ),
    );
  }

  // ── Logout confirmation ───────────────────────────────────────────────────
  void _confirmLogout(BuildContext context, UserCubit cubit) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout',
            style: TextStyle(
                color: Color(0xFF2E251F), fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to log out?',
            style: TextStyle(color: Color(0xFF5E544D))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF8D6E63))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              cubit.logout();
              Navigator.pushNamedAndRemoveUntil(
                context,
                Login.routeName,
                (route) => false,
              );
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ── Card builder ──────────────────────────────────────────────────────────
  Widget _buildCard({
    required IconData icon,
    required String title,
    String? value,
    VoidCallback? onTap,
    bool isEditable = false,
    bool showArrow = false,
    bool isDanger = false,
    IconData? trailingIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.transparentDarkCocoa,
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDanger
                      ? Colors.red.withOpacity(0.1)
                      : const Color(0xFFF4ECE5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: isDanger ? Colors.red : const Color(0xFF8D6E63),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isDanger ? Colors.red : const Color(0xFF2E251F),
                      ),
                    ),
                    if (value != null && value.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF6F655F),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isEditable)
                const Icon(Icons.edit_rounded,
                    size: 18, color: Color(0xFF8D6E63)),
              if (showArrow)
                const Icon(Icons.arrow_forward_ios,
                    size: 16, color: Color(0xFF8D6E63)),
              if (trailingIcon != null)
                Icon(trailingIcon, size: 18, color: const Color(0xFF8D6E63)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Country list ──────────────────────────────────────────────────────────
  Widget _buildCountryList(BuildContext context) {
    final cubit = context.read<UserCubit>();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F5F1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEE2D8)),
      ),
      child: Column(
        children: _countries.map((country) {
          final isSelected = widget.countryController.text == country;
          return ListTile(
            title: Text(
              country,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                color: isSelected
                    ? const Color(0xFF8D6E63)
                    : const Color(0xFF2E251F),
              ),
            ),
            trailing: isSelected
                ? const Icon(Icons.check_rounded, color: Color(0xFF8D6E63))
                : null,
            onTap: () async {
              setState(() {
                widget.countryController.text = country;
                _showCountryOptions = false;
              });
              // Persist to Firestore
              await cubit.updateUserInfoFirebase(country: country);
            },
          );
        }).toList(),
      ),
    );
  }
}
