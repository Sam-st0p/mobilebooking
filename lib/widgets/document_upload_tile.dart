// lib/widgets/document_upload_tile.dart
//
// The dashed "Click to choose a file" upload zone used for verification
// IDs, the emergency contact's ID, the signature image, and the payment
// proof. Validates type + size up front and shows the chosen file with
// Replace / Remove.
//
// Requires the `file_picker` package (image_picker cannot select PDFs):
//   flutter pub add file_picker

import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'dashed_border.dart';

/// Must match BookingDocumentController::MAX_FILE_KB on the backend (4096 KB).
const int kMaxDocumentBytes = 4 * 1024 * 1024;

/// Must stay below PaymentSubmissionController's `max:10240` (10 MB).
const int kMaxPaymentProofBytes = 8 * 1024 * 1024;

const List<String> kIdExtensions = ['jpg', 'jpeg', 'png', 'webp', 'pdf'];
const List<String> kImageExtensions = ['jpg', 'jpeg', 'png', 'webp'];

/// PaymentSubmissionController validates `mimes:jpg,jpeg,png,pdf` — WEBP is
/// rejected there, so it is not offered for payment proofs.
const List<String> kPaymentProofExtensions = ['jpg', 'jpeg', 'png', 'pdf'];

/// A file the customer has chosen but not yet uploaded.
class PickedDocument {
  final Uint8List bytes;
  final String filename;
  final String mimeType;
  const PickedDocument({required this.bytes, required this.filename, required this.mimeType});

  int get sizeBytes => bytes.length;
  bool get isImage => mimeType.startsWith('image/');
}

String? _mimeForExtension(String ext) {
  switch (ext.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'pdf':
      return 'application/pdf';
    default:
      return null;
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// "JPG, PNG, WEBP, or PDF" / "JPG, PNG, or PDF" / "JPG or PNG".
String describeExtensions(List<String> extensions) {
  final labels = <String>[];
  for (final ext in extensions) {
    final label = (ext == 'jpeg' ? 'jpg' : ext).toUpperCase();
    if (!labels.contains(label)) labels.add(label);
  }
  if (labels.length <= 1) return labels.join();
  if (labels.length == 2) return '${labels[0]} or ${labels[1]}';
  return '${labels.sublist(0, labels.length - 1).join(', ')}, or ${labels.last}';
}

class DocumentUploadTile extends StatefulWidget {
  final PickedDocument? value;
  final ValueChanged<PickedDocument?> onChanged;

  /// Read by screen readers, e.g. "First valid ID".
  final String semanticLabel;

  final List<String> allowedExtensions;
  final int maxBytes;

  const DocumentUploadTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.allowedExtensions = kIdExtensions,
    this.maxBytes = kMaxDocumentBytes,
  });

  @override
  State<DocumentUploadTile> createState() => _DocumentUploadTileState();
}

class _DocumentUploadTileState extends State<DocumentUploadTile> {
  String? _error;

  String get _typesText => describeExtensions(widget.allowedExtensions);
  int get _maxMb => widget.maxBytes ~/ (1024 * 1024);
  String get _helperText => '$_typesText · up to ${_maxMb}MB';

  Future<void> _pick() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: widget.allowedExtensions,
        withData: true, // we need the bytes to upload (works on web too)
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      final ext = (file.extension ?? file.name.split('.').last).toLowerCase();
      final mime = _mimeForExtension(ext);

      if (bytes == null) {
        setState(() => _error = 'We could not read that file. Please try another one.');
        return;
      }
      if (mime == null || !widget.allowedExtensions.contains(ext)) {
        setState(() => _error = 'That file type is not supported. Use $_typesText.');
        return;
      }
      if (bytes.length > widget.maxBytes) {
        setState(() => _error = 'That file is ${_formatBytes(bytes.length)}. Please choose one up to ${_maxMb}MB.');
        return;
      }

      setState(() => _error = null);
      widget.onChanged(PickedDocument(bytes: bytes, filename: file.name, mimeType: mime));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'We could not open the file picker. Please try again.');
    }
  }

  void _remove() {
    setState(() => _error = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (file == null) _buildEmpty() else _buildFilled(file),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(color: AppColors.statusRed, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _buildEmpty() {
    return Semantics(
      button: true,
      label: '${widget.semanticLabel}: choose a file. $_helperText',
      onTap: _pick,
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.blush.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _pick,
            child: CustomPaint(
              painter: DashedBorderPainter(
                color: _error != null ? AppColors.statusRed : AppColors.dustyRose,
                radius: 12,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Click to choose a file',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _helperText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: AppColors.charcoal),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilled(PickedDocument file) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.statusGreen.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
              child: file.isImage
                  ? Image.memory(
                      file.bytes,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _fileIcon(Icons.image_outlined),
                    )
                  : _fileIcon(Icons.picture_as_pdf_outlined),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.check_circle, size: 13, color: AppColors.statusGreen),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Ready · ${_formatBytes(file.sizeBytes)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.charcoal),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _pick,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 36),
            ),
            child: const Text('Replace', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            onPressed: _remove,
            tooltip: 'Remove ${widget.semanticLabel}',
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.charcoal,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _fileIcon(IconData icon) => Container(
        color: AppColors.background,
        alignment: Alignment.center,
        child: Icon(icon, color: AppColors.primary),
      );
}