// lib/widgets/availability_badge.dart

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/availability.dart';

/// Port of `components/availability-badge/AvailabilityBadge.tsx`.
class AvailabilityBadge extends StatelessWidget {
  final int totalUnits;
  final int availableUnits;

  const AvailabilityBadge({
    super.key,
    required this.totalUnits,
    required this.availableUnits,
  });

  @override
  Widget build(BuildContext context) {
    final level = getAvailabilityLevel(availableUnits, totalUnits);
    final label = getAvailabilityLabel(level);

    final Color fg;
    final Color bg;
    switch (level) {
      case AvailabilityLevel.available:
        fg = AppColors.statusGreen;
        bg = AppColors.statusGreenBg;
        break;
      case AvailabilityLevel.limited:
        fg = AppColors.statusYellow;
        bg = AppColors.statusYellowBg;
        break;
      case AvailabilityLevel.full:
        fg = AppColors.statusRed;
        bg = AppColors.statusRedBg;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
