import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_text.dart';
import 'package:geoguide/presntation/screens/login%20screen/login.dart';
import 'package:geoguide/presntation/widgets/custom_background.dart';
import 'package:geoguide/presntation/widgets/custom_button.dart';

class Onboarding extends StatefulWidget {
  static String routeName = '/onboarding';
  const Onboarding({super.key});

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  late Animation<double> fade;
  late Animation<Offset> slide;
  late Animation<double> scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    slide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    scale = Tween<double>(
      begin: 0.9,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const themeBg = Color(0xFFF7F1EB);

    return SafeArea(
      child: Scaffold(
        backgroundColor: themeBg,
        body: Stack(
          children: [
            const Positioned.fill(child: CustomBackground()),

            /// Top Title
            Align(
              alignment: Alignment.topCenter,
              child: FadeTransition(
                opacity: fade,
                child: SlideTransition(
                  position: slide,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).size.height * 0.10,
                    ),
                    child: Column(
                      children: [
                        Text(
                          AppText.geoguide,
                          style: TextStyle(
                            fontSize:
                                MediaQuery.of(context).size.width * 0.105,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Explore Egypt beautifully',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            /// Glass Card
            Align(
              alignment: Alignment.center,
              child: ScaleTransition(
                scale: scale,
                child: FadeTransition(
                  opacity: fade,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: BackdropFilter(
                        filter:
                            ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Discover iconic places\nacross Egypt',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Search, explore and save your favorite places easily.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            /// Bottom Panel
            Align(
              alignment: Alignment.bottomCenter,
              child: FadeTransition(
                opacity: fade,
                child: SlideTransition(
                  position: slide,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
                    decoration: const BoxDecoration(
                      color: themeBg,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          AppText.welcome,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 20),

                        /// Animated Button
                        ScaleTransition(
                          scale: scale,
                          child: CustomButton(
                            title: AppText.startButton,
                            formKey: null,
                            icon: Icons.arrow_forward,
                            function: () {
                              Navigator.pushReplacementNamed(
                                context,
                                Login.routeName,
                              );
                            },
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
      ),
    );
  }
}