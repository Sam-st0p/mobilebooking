// lib/widgets/update_dialog.dart
//
// A simple "a new version is available" dialog. "Update Now" opens the APK's
// direct download link in the browser — Android's own download manager and
// your existing "install unknown apps" permission (see AndroidManifest.xml
// notes) take it from there. This avoids needing extra permissions or a
// file-download/installer package just for this.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_checker.dart';
import '../theme/app_theme.dart';

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Update available'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Version ${info.version} is ready to download.'),
          if (info.releaseNotes != null) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Text(info.releaseNotes!, style: const TextStyle(fontSize: 12.5, color: AppColors.charcoal)),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Later'),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            final uri = Uri.parse(info.downloadUrl);
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: const Text('Update Now'),
        ),
      ],
    ),
  );
}