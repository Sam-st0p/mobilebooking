// lib/screens/booking/requirements_screen.dart
//
// Lets the customer see the document requirements attached to a booking
// (auto-created by create_booking from product_requirements) and upload
// against each one. See RequirementService for important caveats about
// there being no dedicated RPC for this — it's direct table inserts
// relying on RLS.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/requirement.dart';
import '../../services/requirement_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/requirement_status_chip.dart';

class RequirementsScreen extends StatefulWidget {
  final String bookingId;
  const RequirementsScreen({super.key, required this.bookingId});

  @override
  State<RequirementsScreen> createState() => _RequirementsScreenState();
}

class _RequirementsScreenState extends State<RequirementsScreen> {
  late Future<List<BookingRequirement>> _requirementsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _requirementsFuture = RequirementService.getRequirementsForBooking(widget.bookingId);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _requirementsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Requirements')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<BookingRequirement>>(
          future: _requirementsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('Could not load requirements. Pull down to try again.')),
                ],
              );
            }
            final requirements = snapshot.data ?? [];
            if (requirements.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No document requirements for this booking.')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: requirements.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _RequirementCard(
                requirement: requirements[i],
                onChanged: () => setState(_load),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RequirementCard extends StatefulWidget {
  final BookingRequirement requirement;
  final VoidCallback onChanged;
  const _RequirementCard({required this.requirement, required this.onChanged});

  @override
  State<_RequirementCard> createState() => _RequirementCardState();
}

class _RequirementCardState extends State<_RequirementCard> {
  bool _uploading = false;
  String? _error;

  Future<void> _upload() async {
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

    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    final Uint8List bytes = await picked.readAsBytes();
    final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      await RequirementService.submitRequirementDocument(
        requirement: widget.requirement,
        bytes: bytes,
        extension: ext,
        originalFilename: picked.name,
        mimeType: 'image/$ext',
      );
      if (!mounted) return;
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.requirement;
    final latest = r.latestSubmission;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(r.requirementNameSnapshot,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              RequirementStatusChip(status: r.status),
            ],
          ),
          if (!r.isRequired) ...[
            const SizedBox(height: 4),
            const Text('Optional', style: TextStyle(color: AppColors.charcoal, fontSize: 12)),
          ],
          if (latest?.reviewNotes != null && latest!.reviewNotes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.statusRedBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('Note: ${latest.reviewNotes}',
                  style: const TextStyle(color: AppColors.statusRed, fontSize: 12.5)),
            ),
          ],
          if (latest?.document != null) ...[
            const SizedBox(height: 10),
            _SubmissionThumbnail(document: latest!.document!),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.statusRed, fontSize: 12)),
          ],
          if (r.needsAction) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : _upload,
                icon: _uploading
                    ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_outlined, size: 18),
                label: Text(latest == null ? 'Upload' : 'Re-upload'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubmissionThumbnail extends StatelessWidget {
  final CustomerDocument document;
  const _SubmissionThumbnail({required this.document});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: RequirementService.getSignedPreviewUrl(document),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(height: 80, width: 80, color: AppColors.lightGray);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snapshot.data!,
            height: 80,
            width: 80,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                Container(height: 80, width: 80, color: AppColors.lightGray),
          ),
        );
      },
    );
  }
}