// lib/widgets/booking_status_chip.dart

import 'package:flutter/material.dart';
import '../models/booking.dart';
import '../theme/app_theme.dart';

class BookingStatusChip extends StatelessWidget {
  final BookingStatus status;
  const BookingStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final Color fg;
    final Color bg;
    switch (status) {
      case BookingStatus.approved:
      case BookingStatus.active:
      case BookingStatus.completed:
        fg = AppColors.statusGreen;
        bg = AppColors.statusGreenBg;
        break;
      case BookingStatus.pendingReview:
        fg = AppColors.statusYellow;
        bg = AppColors.statusYellowBg;
        break;
      case BookingStatus.rejected:
      case BookingStatus.cancelled:
        fg = AppColors.statusRed;
        bg = AppColors.statusRedBg;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        bookingStatusLabel(status),
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}