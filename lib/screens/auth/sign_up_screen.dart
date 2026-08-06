// lib/screens/auth/sign_in_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Port of `app/(auth)/sign-up/SignUpForm.tsx`. Same email OTP flow as
/// sign-in, but with shouldCreateUser: true.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  String? _formError;
  bool _submitting = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _formError = null;
      _submitting = true;
    });
    try {
      final email = _emailController.text.trim();
      await AuthService.sendEmailOtp(email, shouldCreateUser: true);
      if (!mounted) return;
      context.push('/verify-email?email=${Uri.encodeComponent(email)}&flow=sign-up');
    } catch (_) {
      setState(() {
        _formError = "We couldn't send a code to that email. Check the address and try again.";
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
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
                "Enter your email and we'll send you a 6-digit one-time code to verify it and finish creating your account.",
                style: TextStyle(color: AppColors.charcoal),
              ),
              const SizedBox(height: 24),
              if (_formError != null) ...[
                Text(_formError!, style: const TextStyle(color: AppColors.calendarBooked)),
                const SizedBox(height: 12),
              ],
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
