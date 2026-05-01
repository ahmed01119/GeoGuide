import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/constants/app_text.dart';
import 'package:geoguide/cubit/user-state.dart';
import 'package:geoguide/cubit/user_cubit.dart';
import 'package:geoguide/presntation/screens/password_configuration/successful_mission.dart';
import 'package:geoguide/presntation/widgets/custom-scaffold.dart';
import 'package:geoguide/presntation/widgets/custom-text-field.dart';
import 'package:geoguide/presntation/widgets/custom_button.dart';
import 'package:geoguide/presntation/widgets/text-container.dart';

class ResetPassword extends StatefulWidget {
  static String routeName = '/resetPassword';
  final bool needCurrentPassword;

  const ResetPassword({super.key, this.needCurrentPassword = false});

  @override
  State<ResetPassword> createState() => _ResetPasswordState();
}

class _ResetPasswordState extends State<ResetPassword> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _currentPasswordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isCurrentPasswordVisible = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _currentPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    if (widget.needCurrentPassword) {
      // Change password from settings — use real Firebase reauthentication
      context.read<UserCubit>().changePassword(
            currentPassword: _currentPasswordController.text.trim(),
            newPassword: _passwordController.text.trim(),
          );
    } else {
      // Reset password flow (arrived via email link / forgot password)
      // Firebase handles the actual reset; just navigate to success
      setState(() => _isLoading = false);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) =>
              const SuccessfulMission(textType: '/resetPassword'),
        ),
        (route) => false,
      );
    }
  }

  Widget _buildPasswordField({
    required String hint,
    required bool obscure,
    required VoidCallback toggle,
    required TextEditingController controller,
    required String? Function(String?) validator,
    String? helperText,
    TextStyle? helperStyle,
  }) {
    return CustomTextField(
      controller: controller,
      obscureText: !obscure,
      validator: validator,
      helperText: helperText,
      helperStyle: helperStyle,
      onChanged: (_) {},
      hintText: hint,
      suffixIcon: IconButton(
        icon: Icon(
          obscure ? Icons.visibility : Icons.visibility_off,
          color: AppColors.hintText,
        ),
        onPressed: toggle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final height = size.height;

    return BlocListener<UserCubit, UserState>(
      listenWhen: (prev, curr) =>
          curr is ChangePasswordSuccess || curr is ChangePasswordFailure,
      listener: (context, state) {
        setState(() => _isLoading = false);

        if (state is ChangePasswordSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password changed successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const SuccessfulMission(textType: '/resetPassword'),
            ),
            (route) => false,
          );
        } else if (state is ChangePasswordFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errMessage),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      child: CustomScaffold(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 30),
            child: TextContainer(
              text: AppText.resetPassword,
              textAlign: TextAlign.center,
              fontSize: 28,
            ),
          ),
          Form(
            key: _formKey,
            child: Column(
              children: [
                if (widget.needCurrentPassword) ...[
                  _buildPasswordField(
                    hint: AppText.currentPassword,
                    obscure: _isCurrentPasswordVisible,
                    toggle: () => setState(() =>
                        _isCurrentPasswordVisible =
                            !_isCurrentPasswordVisible),
                    controller: _currentPasswordController,
                    validator: (value) =>
                        (value == null || value.isEmpty)
                            ? AppText.setCurrentPassword
                            : null,
                  ),
                  SizedBox(height: height * 0.02),
                ],
                _buildPasswordField(
                  hint: AppText.password,
                  obscure: _isPasswordVisible,
                  toggle: () => setState(
                      () => _isPasswordVisible = !_isPasswordVisible),
                  controller: _passwordController,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppText.enterPassword;
                    }
                    if (value.length < 8 || value.length > 20) {
                      return AppText.passwordValidator3;
                    }
                    if (!RegExp(r'[A-Z]').hasMatch(value)) {
                      return AppText.passwordValidation1;
                    }
                    if (!RegExp(r'[a-z]').hasMatch(value)) {
                      return AppText.passwordValidation2;
                    }
                    if (!RegExp(r'[0-9]').hasMatch(value)) {
                      return AppText.passwordValidation3;
                    }
                    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]')
                        .hasMatch(value)) {
                      return AppText.passwordValidation4;
                    }
                    return null;
                  },
                  helperText: AppText.passwordHintText,
                  helperStyle:
                      const TextStyle(color: AppColors.hintText),
                ),
                SizedBox(height: height * 0.02),
                _buildPasswordField(
                  hint: AppText.confirmPassword,
                  obscure: _isConfirmPasswordVisible,
                  toggle: () => setState(() =>
                      _isConfirmPasswordVisible =
                          !_isConfirmPasswordVisible),
                  controller: _confirmPasswordController,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppText.enterPassword;
                    }
                    if (value != _passwordController.text) {
                      return AppText.passwordsDoNotMatch;
                    }
                    return null;
                  },
                ),
                SizedBox(height: height * 0.03),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : CustomButton(
                        title: AppText.reset,
                        formKey: _formKey,
                        function: _submit,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}