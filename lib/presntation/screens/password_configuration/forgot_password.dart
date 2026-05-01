import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/constants/app_text.dart';
import 'package:geoguide/presntation/screens/login%20screen/login.dart';
import 'package:geoguide/presntation/widgets/clickable-text.dart';
import 'package:geoguide/presntation/widgets/custom-scaffold.dart';
import 'package:geoguide/presntation/widgets/custom-text-field.dart';
import 'package:geoguide/presntation/widgets/custom_button.dart';
import 'package:geoguide/presntation/widgets/text-container.dart';

class ForgotPassword extends StatefulWidget {
  static String routeName = '/forgotPassword';

  const ForgotPassword({super.key});

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();

  bool _isLoading = false;

  Future<void> _sendResetEmail() async {
  if (_formKey.currentState?.validate() != true) return;

  setState(() => _isLoading = true);

  try {
    final email = _emailController.text.trim().toLowerCase();

    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    debugPrint('RESET EMAIL SENT TO: $email');
    debugPrint('AUTH CURRENT LANG: ${FirebaseAuth.instance.languageCode}');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reset link sent to your email'),
        backgroundColor: Colors.green,
      ),
      
    );

    Navigator.pushReplacementNamed(context, Login.routeName);
  } catch (e) {
    debugPrint('ERROR SENDING RESET EMAIL: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Failed to send reset email'),
        backgroundColor: Colors.red,
      ),
    );
    
  } finally {
    setState(() => _isLoading = false);
  }
}

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final height = size.height;
    final width = size.width;

    return CustomScaffold(
      children: [
        const SizedBox(height: 8),

        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withOpacity(0.18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextContainer(
                    text: AppText.forgotPassword,
                    fontSize: 28,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter your email and we will send you a password reset link.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        SizedBox(height: height * 0.035),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Form(
                key: _formKey,
                child: CustomTextField(
                  controller: _emailController,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppText.emailValidator1;
                    } else if (!RegExp(
                      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                    ).hasMatch(value)) {
                      return AppText.emailValidator2;
                    }
                    return null;
                  },
                  onChanged: (value) {
                    _emailController.value = TextEditingValue(
                      text: value.toLowerCase().trim(),
                      selection: TextSelection.collapsed(
                        offset: value.length,
                      ),
                    );
                  },
                  hintText: AppText.email,
                ),
              ),

              SizedBox(height: height * 0.025),

              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : CustomButton(
                      title: AppText.send,
                      icon: Icons.mail_outline_rounded,
                      function: _sendResetEmail,
                      formKey: _formKey,
                    ),
            ],
          ),
        ),

        SizedBox(height: height * 0.035),

        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.65),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                AppText.rememberedIt,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF5E544D),
                ),
              ),
              SizedBox(width: width * 0.01),
              ClickableText(
                title: AppText.signIn,
                size: 15,
                color: AppColors.brown,
                function: () {
                  Navigator.pushReplacementNamed(context, Login.routeName);
                },
                fontWeight: FontWeight.bold,
              ),
            ],
          ),
        ),
      ],
    );
  }
}