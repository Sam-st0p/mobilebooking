// lib/widgets/reservation_stepper.dart
//
// The 6-step progress indicator from the guided reservation flow:
//   1 Rental Details -> 2 Reservation -> 3 Payment Submission ->
//   4 Verification Documents -> 5 Rental Agreement -> 6 Booking Confirmation
//
// Completed steps show a check, the current step shows its number with a
// rose ring and rose label, and upcoming steps are muted. On narrow screens
// (phones) six full labels can't fit, so only the current step's label is
// shown beneath the row of circles.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ReservationStepper extends StatelessWidget {
  /// Zero-based index of the current step (0 = Rental Details ... 5 = Booking
  /// Confirmation).
  final int currentIndex;
  const ReservationStepper({super.key, required this.currentIndex});

  static const labels = <String>[
    'Rental Details',
    'Reservation',
    'Payment Submission',
    'Verification Documents',
    'Rental Agreement',
    'Booking Confirmation',
  ];

  static const _mutedBorder = Color(0xFFD0D0CC);
  static const _circleSize = 28.0;

  @override
  Widget build(BuildContext context) {
    final current = currentIndex.clamp(0, labels.length - 1).toInt();

    return Semantics(
      container: true,
      label: 'Step ${current + 1} of ${labels.length}: ${labels[current]}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Expanded(child: _node(i, current, showLabel: !compact)),
                  ],
                ),
                if (compact) ...[
                  const SizedBox(height: 8),
                  Text(
                    labels[current],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _node(int i, int current, {required bool showLabel}) {
    final isDone = i < current;
    final isCurrent = i == current;

    // The line to the LEFT of step i joins step i-1 and i; it is "filled"
    // once step i has been reached. The line to the RIGHT joins i and i+1;
    // it is filled once step i+1 has been reached.
    final leftFilled = i <= current;
    final rightFilled = i + 1 <= current;

    Widget line(bool visible, bool filled) => Expanded(
          child: visible
              ? Container(height: 2, color: filled ? AppColors.primary : AppColors.lightGray)
              : const SizedBox.shrink(),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _circleSize,
          child: Row(
            children: [
              line(i > 0, leftFilled),
              _circle(i, isDone: isDone, isCurrent: isCurrent),
              line(i < labels.length - 1, rightFilled),
            ],
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              labels[i],
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.25,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                color: isCurrent
                    ? AppColors.primary
                    : (isDone ? AppColors.textPrimary : AppColors.charcoal),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _circle(int i, {required bool isDone, required bool isCurrent}) {
    if (isDone) {
      return Container(
        width: _circleSize,
        height: _circleSize,
        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 16, color: AppColors.white),
      );
    }
    return Container(
      width: _circleSize,
      height: _circleSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: isCurrent ? AppColors.primary : _mutedBorder,
          width: isCurrent ? 2 : 1.5,
        ),
      ),
      child: Text(
        '${i + 1}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isCurrent ? AppColors.primary : AppColors.charcoal,
        ),
      ),
    );
  }
}