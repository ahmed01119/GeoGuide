import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/presntation/screens/admin/admin_cleanup_tools.dart';
import 'package:geoguide/presntation/screens/admin/admin_guard.dart';
import 'package:geoguide/presntation/screens/admin/admin_places_management.dart';
import 'package:geoguide/presntation/screens/admin/admin_review_queue.dart';
import 'package:geoguide/presntation/screens/admin/admin_users_management.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  static const routeName = '/admin-dashboard';

  @override
  Widget build(BuildContext context) {
    final cards = <({String title, String subtitle, IconData icon, Widget page})>[
      (
        title: 'Places Management',
        subtitle: 'Search, filter, edit, hide/unhide, approve places.',
        icon: Icons.location_city_rounded,
        page: const AdminPlacesManagement(),
      ),
      (
        title: 'Review Queue',
        subtitle: 'Review needsReview/city/image/outing/invalid flags.',
        icon: Icons.fact_check_rounded,
        page: const AdminReviewQueue(),
      ),
      (
        title: 'Cleanup Tools',
        subtitle: 'Run city cleanup and duplicate/manual tools.',
        icon: Icons.cleaning_services_rounded,
        page: const AdminCleanupTools(),
      ),
      (
        title: 'Users Management',
        subtitle: 'Block/unblock users and update roles.',
        icon: Icons.manage_accounts_rounded,
        page: const AdminUsersManagement(),
      ),
    ];

    return AdminGuard(
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F1EB),
        appBar: AppBar(
          title: const Text('Admin Panel'),
          backgroundColor: AppColors.chestnutBrown,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.chestnutBrown.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.chestnutBrown.withOpacity(0.18),
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Admin Workspace',
                        style: TextStyle(
                          color: Color(0xFF2E251F),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Manage places, review queue, cleanup tools, and users.',
                        style: TextStyle(
                          color: Color(0xFF5E544D),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...cards.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
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
                    ),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFF4ECE5),
                        child: Icon(c.icon, color: AppColors.chestnutBrown),
                      ),
                      title: Text(
                        c.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2E251F),
                        ),
                      ),
                      subtitle: Text(c.subtitle),
                      trailing: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: Color(0xFF8D6E63),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => c.page),
                        );
                      },
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
