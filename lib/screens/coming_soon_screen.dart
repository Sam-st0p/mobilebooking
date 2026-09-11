// lib/screens/coming_soon_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Placeholder for screens not yet ported (reservation flow, account
/// section). Swap these out screen-by-screen in phase 2 — see README.md.
class ComingSoonScreen extends StatelessWidget {
  final String title;
  final String note;

  const ComingSoonScreen({super.key, required this.title, this.note = ''});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.construction_outlined, size: 40, color: AppColors.primary),
              const SizedBox(height: 12),
              Text('$title — coming soon',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(note, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.charcoal)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
  