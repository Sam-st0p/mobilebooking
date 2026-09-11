// lib/screens/account/profile_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/user_profile.dart';
import '../../services/auth_provider.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';

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
      setState(() => _error = 'Could not save your profile. Please try again.');
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
      setState(() => _error = 'Could not update your photo. Please try again.');
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
        Text('Email', style: _labelStyle),
        const SizedBox(height: 4),
        Text(profile.email, style: const TextStyle(color: AppColors.charcoal)),
        const SizedBox(height: 20),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Full name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone number'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _addressController,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Full address'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _facebookController,
          decoration: const InputDecoration(labelText: 'Facebook link (optional)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _instagramController,
          decoration: const InputDecoration(labelText: 'Instagram link (optional)'),
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
            onPressed: _saving ? null : () => _save(profile.id),
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
      ],
    );
  }

  static const _labelStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.charcoal);
}