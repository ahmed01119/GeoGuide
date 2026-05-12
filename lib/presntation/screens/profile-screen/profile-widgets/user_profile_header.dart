import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geoguide/constants/app_assets.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/cubit/user_cubit.dart';
import 'package:geoguide/models.dart/user-model.dart';
import 'package:image_picker/image_picker.dart';

class UserProfileHeader extends StatefulWidget {
  final UserModel user;
  final String imageUrl;

  const UserProfileHeader({
    super.key,
    required this.user,
    required this.imageUrl,
  });

  @override
  State<UserProfileHeader> createState() => _UserProfileHeaderState();
}

class _UserProfileHeaderState extends State<UserProfileHeader> {
  Uint8List? _pickedImageBytes;
  bool _isUploading = false;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 60,
      maxWidth: 800,
    );

    if (picked == null) return;

    final bytes = await picked.readAsBytes();

    setState(() {
      _pickedImageBytes = bytes;
      _isUploading = true;
    });

    final ok =
        await context.read<UserCubit>().updateProfileImageCloudinary(picked);

    if (!mounted) return;

    setState(() {
      _isUploading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Profile image updated' : 'Could not update image'),
      ),
    );
  }

  ImageProvider _getProfileImage() {
    if (_pickedImageBytes != null) {
      return MemoryImage(_pickedImageBytes!);
    }

    if (widget.imageUrl.trim().isNotEmpty) {
      return NetworkImage(widget.imageUrl.trim());
    }

    return const AssetImage(AppAssets.unknown);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.18),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.22),
                      width: 4,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: const Color(0xFFF4ECE5),
                    backgroundImage: _getProfileImage(),
                  ),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(50),
                    onTap: _isUploading ? null : _pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: AppColors.chestnutBrown,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 260,
                  child: Text(
                    widget.user.name.isNotEmpty
                        ? widget.user.name
                        : 'No Name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildInfoChip(
                      icon: Icons.verified_user_rounded,
                      label: widget.user.role.isNotEmpty
                          ? widget.user.role
                          : 'User',
                    ),
                    _buildInfoChip(
                      icon: Icons.flag_rounded,
                      label: widget.user.country.isNotEmpty
                          ? widget.user.country
                          : 'Not set',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withOpacity(0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}