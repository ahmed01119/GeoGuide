import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geoguide/constants/app_colors.dart';
import 'package:geoguide/constants/app_text.dart';
import 'package:geoguide/cubit/user_cubit.dart';

class EditPhoneDialog extends StatefulWidget {
  final String currentPhone;

  const EditPhoneDialog({
    super.key,
    required this.currentPhone,
  });

  @override
  State<EditPhoneDialog> createState() => _EditPhoneDialogState();
}

class _EditPhoneDialogState extends State<EditPhoneDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phoneController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.currentPhone);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _savePhone() async {
    if (!_formKey.currentState!.validate()) return;

    final phone = _phoneController.text.trim();

    setState(() => _isSaving = true);

    final success = await context.read<UserCubit>().updateUserInfoFirebase(
          phone: phone,
        );

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (success) {
      Navigator.pop(context, phone);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phone number updated successfully'),
          backgroundColor: Color(0xFF8D6E63),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update phone number'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderSide: BorderSide(color: color),
      borderRadius: BorderRadius.circular(16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F5F1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFEEE2D8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.chestnutBrown.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.phone_rounded,
                      color: AppColors.chestnutBrown,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      AppText.editPhone,
                      style: TextStyle(
                        color: Color(0xFF2E251F),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Update your phone number and save it to your profile.',
                style: TextStyle(
                  color: Color(0xFF7E746C),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: AppText.enterPhoneNumber,
                  hintStyle: const TextStyle(color: AppColors.taupeGray),
                  enabledBorder: _border(const Color(0xFFE2D7CC)),
                  focusedBorder: _border(AppColors.chestnutBrown),
                  errorBorder: _border(Colors.red),
                  focusedErrorBorder: _border(Colors.red),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return AppText.enterYourPhone;
                  }

                  final phoneRegex = RegExp(r'^01[0-9]{9}$');
                  if (!phoneRegex.hasMatch(value.trim())) {
                    return AppText.invalidPhoneNumber;
                  }

                  return null;
                },
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.chestnutBrown,
                        side: const BorderSide(
                          color: AppColors.chestnutBrown,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text(
                        AppText.cancel,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: AppColors.chestnutBrown,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _isSaving ? null : _savePhone,
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              AppText.save,
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}