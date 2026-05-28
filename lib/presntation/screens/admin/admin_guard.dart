import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_injector.dart';
import 'package:geoguide/constants/app_colors.dart';

class AdminGuard extends StatelessWidget {
  const AdminGuard({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AppInjector.firebase.isCurrentUserAdmin(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFFF7F1EB),
            body: Center(
              child: CircularProgressIndicator(color: AppColors.chestnutBrown),
            ),
          );
        }
        if (snap.data != true) {
          return Scaffold(
            backgroundColor: const Color(0xFFF7F1EB),
            appBar: AppBar(
              title: const Text('Admin Access'),
              backgroundColor: AppColors.chestnutBrown,
            ),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'You are not authorized to access admin tools.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5E544D),
                  ),
                ),
              ),
            ),
          );
        }
        return child;
      },
    );
  }
}
