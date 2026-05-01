import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_assets.dart';

class CustomBackground extends StatelessWidget {
  const CustomBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Image.asset(
            AppAssets.background,
            fit: BoxFit.cover,
          ),
        ),

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Image.asset(
            AppAssets.shadow,
            fit: BoxFit.fitWidth,
            width: double.infinity,
          ),
        ),

        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.10),
                  Colors.black.withOpacity(0.04),
                  Colors.black.withOpacity(0.18),
                ],
              ),
            ),
          ),
        ),

        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.2),
                radius: 1.1,
                colors: [
                  const Color(0xFFFFD7B8).withOpacity(0.16),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFFF7F1EB).withOpacity(0.20),
                    const Color(0xFFF7F1EB).withOpacity(0.78),
                  ],
                ),
              ),
            ),
          ),
        ),

        Positioned.fill(
          child: Container(
            color: const Color(0xFF8D6E63).withOpacity(0.05),
          ),
        ),
      ],
    );
  }
}