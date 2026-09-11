// lib/screens/auth/verify_email_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../services/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Port of `app/(auth)/verify-email/VerifyEmailForm.tsx`. Confirms the
/// 6-digit code sent by sign-in/sign-up, then routes into the app.
class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final String flow; // "sign-in" | "sign-up"
  final SignUpProfile? signUpProfile; // required to resend a sign-up code

  const VerifyEmailScreen({
    super.key,
    required this.email,
    required this.flow,
    this.signUpProfile,
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeController = TextEditingController();
  String? _formError;
  bool _submitting = false;
  bool _resending = false;

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _formError = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _formError = null;
      _submitting = true;
    });
    try {
      final signedInUser = await AuthService.verifyEmailOtp(widget.email, code);
      if (!mounted) return;
      await context.read<AppAuth>().onSignedIn(signedInUser);
      if (!mounted) return;
      context.go('/account/bookings');
    } catch (e) {
      setState(() {
        _formError = 'That code is invalid or has expired. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      if (widget.flow == 'sign-up') {
        final profile = widget.signUpProfile;
        if (profile == null) {
          throw Exception('Please go back and fill in the sign-up form again to resend.');
        }
        await AuthService.sendSignUpOtp(widget.email, profile);
      } else {
        await AuthService.sendSignInOtp(widget.email);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been sent.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is Exception ? e.toString().replaceFirst('Exception: ', '') : "Couldn't resend the code. Please try again.")),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Your Email')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the 6-digit code sent to ${widget.email}',
              style: const TextStyle(color: AppColors.charcoal),
            ),
            const SizedBox(height: 24),
            if (_formError != null) ...[
              Text(_formError!, style: const TextStyle(color: AppColors.calendarBooked)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: const InputDecoration(counterText: ''),
            ),
            const SizedBox(height: 12),
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
                    : const Text('Verify & Continue'),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _resending ? null : _resend,
                child: Text(_resending ? 'Sending…' : "Didn't get a code? Resend"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
