// lib/widgets/requirement_status_chip.dart

import 'package:flutter/material.dart';
import '../models/requirement.dart';
import '../theme/app_theme.dart';

class RequirementStatusChip extends StatelessWidget {
  final RequirementStatus status;
  const RequirementStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final Color fg;
    final Color bg;
    switch (status) {
      case RequirementStatus.approved:
      case RequirementStatus.waived:
        fg = AppColors.statusGreen;
        bg = AppColors.statusGreenBg;
        break;
      case RequirementStatus.pendingReview:
        fg = AppColors.statusYellow;
        bg = AppColors.statusYellowBg;
        break;
      case RequirementStatus.pendingSubmission:
      case RequirementStatus.rejected:
        fg = AppColors.statusRed;
        bg = AppColors.statusRedBg;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        requirementStatusLabel(status),
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}