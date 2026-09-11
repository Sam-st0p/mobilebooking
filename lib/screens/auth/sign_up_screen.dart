// lib/screens/auth/sign_in_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Sign-up now collects name/phone/birthdate upfront (matching the web
/// app's expanded form) — still email-OTP only, no password. Birthdate
/// must be 18+ and is saved once to apply a birthday-month discount later.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  DateTime? _birthDate;
  String? _formError;
  bool _submitting = false;

  static final DateTime _maxBirthDate = DateTime.now().subtract(const Duration(days: 365 * 18));

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _maxBirthDate,
      firstDate: DateTime(1900),
      lastDate: _maxBirthDate,
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_birthDate == null) {
      setState(() => _formError = 'Birthdate is required.');
      return;
    }
    setState(() {
      _formError = null;
      _submitting = true;
    });
    try {
      final email = _emailController.text.trim();
      await AuthService.sendSignUpOtp(
        email,
        SignUpProfile(
          displayName: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          birthDate: _formatDate(_birthDate!),
        ),
      );
      if (!mounted) return;
      context.push(
        '/verify-email?email=${Uri.encodeComponent(email)}&flow=sign-up',
        extra: SignUpProfile(
          displayName: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          birthDate: _formatDate(_birthDate!),
        ),
      );
    } catch (e) {
      setState(() {
        _formError = "We couldn't send a code to that email. Check the address and try again.";
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CUSTOMER ACCOUNT',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 8),
              const Text('Create Account', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                'Add your basic contact details, then verify your email with a secure '
                '6-digit code. No password is needed for customer accounts.',
                style: TextStyle(color: AppColors.charcoal),
              ),
              const SizedBox(height: 20),
              if (_formError != null) ...[
                Text(_formError!, style: const TextStyle(color: AppColors.calendarBooked)),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (value) =>
                    (value == null || value.trim().length < 2) ? 'Enter your complete name' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                decoration: const InputDecoration(
                  labelText: 'Active phone number',
                  hintText: '09XXXXXXXXX',
                  helperText: 'Use exactly 11 digits.',
                ),
                validator: (value) =>
                    (value == null || !RegExp(r'^\d{11}$').hasMatch(value))
                        ? 'Phone number must contain exactly 11 digits'
                        : null,
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickBirthDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Birthdate',
                    helperText: 'Used to apply the ₱100 birthday-month discount.',
                  ),
                  child: Text(
                    _birthDate == null ? 'Select date' : _formatDate(_birthDate!),
                    style: TextStyle(color: _birthDate == null ? AppColors.charcoal : AppColors.textPrimary),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email address'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Email is required';
                  if (!value.contains('@')) return 'Enter a valid email address';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                        )
                      : const Text('Send Code'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => context.push('/sign-in'),
                  child: const Text('Already have an account? Sign in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
