// lib/screens/account/profile_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/user_profile.dart';
import '../../services/auth_provider.dart';
import '../../services/profile_service.dart';
import '../../services/update_checker.dart';
import '../../theme/app_theme.dart';
import '../../widgets/form_layout.dart';
import '../../widgets/update_dialog.dart';

/// Port of `app/account/profile/page.tsx`.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();

  bool _initialized = false;
  bool _saving = false;
  bool _uploadingPhoto = false;
  String? _error;
  String? _successMessage;

  void _loadFrom(UserProfile profile) {
    _nameController.text = profile.displayName;
    _phoneController.text = profile.phoneNumber ?? '';
    _addressController.text = profile.fullAddress ?? '';
    _facebookController.text = profile.facebookLink ?? '';
    _instagramController.text = profile.instagramLink ?? '';
    _initialized = true;
  }

  bool get _nameValid => _nameController.text.trim().length >= 2;
  bool get _phoneValid => RegExp(r'^\d{11}$').hasMatch(_phoneController.text.trim());
  bool get _canSave => _nameValid && _phoneValid && !_saving;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    super.dispose();
  }

  Future<void> _save(String uid) async {
    setState(() {
      _saving = true;
      _error = null;
      _successMessage = null;
    });
    try {
      await ProfileService.updateUserProfile(
        uid,
        displayName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        fullAddress: _addressController.text.trim(),
        facebookLink: _facebookController.text.trim(),
        instagramLink: _instagramController.text.trim(),
      );
      if (!mounted) return;
      await context.read<AppAuth>().refreshProfile();
      if (!mounted) return;
      setState(() => _successMessage = 'Profile updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePhoto(String uid) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 800);
    if (picked == null) return;

    setState(() {
      _uploadingPhoto = true;
      _error = null;
    });
    try {
      final Uint8List bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      await ProfileService.uploadProfilePhoto(uid, bytes, ext);
      if (!mounted) return;
      await context.read<AppAuth>().refreshProfile();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AppAuth>().signOut();
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuth>();
    final profile = auth.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: auth.loading
          ? const Center(child: CircularProgressIndicator())
          : profile == null
              ? const Center(child: Text('We could not load your profile.'))
              : _buildForm(profile),
    );
  }

  Widget _buildForm(UserProfile profile) {
    if (!_initialized) _loadFrom(profile);
    final photoUrl = profile.photoUrl;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Stack(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: AppColors.lightGray,
                backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                child: photoUrl == null
                    ? const Icon(Icons.person, size: 44, color: AppColors.charcoal)
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Material(
                  color: AppColors.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _uploadingPhoto ? null : () => _changePhoto(profile.id),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _uploadingPhoto
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                            )
                          : const Icon(Icons.camera_alt, size: 16, color: AppColors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LabeledField(
          label: 'Email',
          required: false,
          note: 'You sign in with this email, so it can\'t be changed here.',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(child: Text(profile.email, style: const TextStyle(color: AppColors.charcoal))),
                const Icon(Icons.lock_outline, size: 16, color: AppColors.charcoal),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Full name',
          child: TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _successMessage = null),
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Phone number',
          note: 'Use exactly 11 digits.',
          noteColor: _phoneController.text.isNotEmpty && !_phoneValid ? AppColors.statusRed : AppColors.charcoal,
          child: TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
            decoration: const InputDecoration(hintText: '09XXXXXXXXX'),
            onChanged: (_) => setState(() => _successMessage = null),
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Full address',
          required: false,
          child: TextField(
            controller: _addressController,
            maxLines: 2,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'House/unit number, street, subdivision, and barangay'),
            onChanged: (_) => setState(() => _successMessage = null),
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Facebook link (optional)',
          required: false,
          child: TextField(
            controller: _facebookController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'https://facebook.com/yourprofile'),
            onChanged: (_) => setState(() => _successMessage = null),
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Instagram link (optional)',
          required: false,
          child: TextField(
            controller: _instagramController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: 'https://instagram.com/yourprofile'),
            onChanged: (_) => setState(() => _successMessage = null),
          ),
        ),
        const SizedBox(height: 20),
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: AppColors.statusRed)),
          const SizedBox(height: 12),
        ],
        if (_successMessage != null) ...[
          Text(_successMessage!, style: const TextStyle(color: AppColors.statusGreen)),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _canSave ? () => _save(profile.id) : null,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                  )
                : const Text('Save Changes'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _confirmSignOut,
            child: const Text('Sign Out'),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Column(
            children: [
              const Text('App version $kAppVersion', style: TextStyle(fontSize: 11.5, color: AppColors.charcoal)),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _checkingForUpdate ? null : _checkForUpdateManually,
                child: _checkingForUpdate
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Check for updates', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _checkingForUpdate = false;

  Future<void> _checkForUpdateManually() async {
    setState(() => _checkingForUpdate = true);
    // Verbose check: unlike the silent one run at launch, this one is allowed
    // to tell you WHY nothing happened — a failed check used to look
    // identical to "you're up to date", which made a wrong repo name or a
    // network problem invisible.
    final result = await checkForUpdateVerbose();
    if (!mounted) return;
    setState(() => _checkingForUpdate = false);

    if (result.hasUpdate) {
      showUpdateDialog(context, result.update!);
    } else if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not check for updates: ${result.error}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're on the latest version.")),
      );
    }
  }

  static const _labelStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.charcoal);
}