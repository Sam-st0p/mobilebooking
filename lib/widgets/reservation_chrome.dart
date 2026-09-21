// lib/widgets/reservation_chrome.dart
//
// The framing shared by all six steps of the guided reservation: the pink
// "Guided Reservation" hero, the green saved-progress banner, the 6-step
// stepper, the "Your selected rental" summary (a sidebar on wide screens, a
// collapsible card on phones), the numbered step card, and the pinned
// Back / Continue bar.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'reservation_stepper.dart';

// ---------------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------------

String _groupThousands(String digits) =>
    digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

/// 2250 -> "PHP2,250", 449.5 -> "PHP449.50". Matches the sidebar / hero
/// style of the web app (currency code, no space, no trailing .00).
String formatMoney(String currency, double amount) {
  final hasCents = amount.truncateToDouble() != amount;
  final fixed = amount.toStringAsFixed(hasCents ? 2 : 0);
  final parts = fixed.split('.');
  return '$currency${_groupThousands(parts[0])}${parts.length > 1 ? '.${parts[1]}' : ''}';
}

/// 1125 -> "PHP 1,125.00". Matches the payment step's summary style
/// (space after a currency code, always two decimals).
String formatMoneyExact(String currency, double amount) {
  final parts = amount.toStringAsFixed(2).split('.');
  final space = currency.length > 1 ? ' ' : '';
  return '$currency$space${_groupThousands(parts[0])}.${parts[1]}';
}

String formatUnits(int n) => '$n ${n == 1 ? 'unit' : 'units'}';

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class ReservationHero extends StatelessWidget {
  /// Null while the booking is still loading — shows a generic title.
  final String? productName;

  /// e.g. "PHP450". Null hides the daily-rate card.
  final String? dailyRateLabel;

  const ReservationHero({super.key, this.productName, this.dailyRateLabel});

  @override
  Widget build(BuildContext context) {
    final title = productName == null ? 'Reserve your rental' : 'Reserve $productName';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.blush.withValues(alpha: 0.85),
            AppColors.blush.withValues(alpha: 0.30),
          ],
        ),
        border: Border.all(color: AppColors.dustyRose),
        borderRadius: BorderRadius.circular(16),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 600;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'GUIDED RESERVATION',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(fontSize: wide ? 30 : 22, height: 1.15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose your schedule, pay securely, submit verification, and sign the agreement.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.charcoal),
              ),
            ],
          );
          final rate = dailyRateLabel == null ? null : _RateCard(label: dailyRateLabel!);
          if (wide && rate != null) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: text),
                const SizedBox(width: 16),
                rate,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              text,
              if (rate != null) ...[const SizedBox(height: 12), rate],
            ],
          );
        },
      ),
    );
  }
}

class _RateCard extends StatelessWidget {
  final String label;
  const _RateCard({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.85),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Daily rate', style: TextStyle(fontSize: 11, color: AppColors.charcoal)),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
          const Text('per rental day', style: TextStyle(fontSize: 11, color: AppColors.charcoal)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Saved progress banner
// ---------------------------------------------------------------------------

class SavedProgressBanner extends StatelessWidget {
  final DateTime savedAt;

  /// true  -> "Your saved progress was restored" (loaded from storage)
  /// false -> "Progress saved on this device"   (saved during this session)
  final bool restored;

  const SavedProgressBanner({super.key, required this.savedAt, this.restored = false});

  static String _time(DateTime t) {
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour12:$minute ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.statusGreenBg,
        border: Border.all(color: AppColors.statusGreen.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle),
            child: const Icon(Icons.check, size: 15, color: AppColors.statusGreen),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  restored ? 'Your saved progress was restored' : 'Progress saved on this device',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.statusGreen),
                ),
                const SizedBox(height: 2),
                Text(
                  'Last saved ${_time(savedAt)}. Verification files and signature images are not stored.',
                  style: const TextStyle(fontSize: 11.5, height: 1.35, color: AppColors.charcoal),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "Your selected rental" summary
// ---------------------------------------------------------------------------

class SelectedRentalCard extends StatefulWidget {
  final String productName;
  final int quantity;

  /// Already formatted, e.g. "PHP2,250" — or "Choose dates" before dates
  /// have been picked.
  final String totalLabel;

  /// Total units of this item the shop owns ("Rental inventory"). Hidden
  /// when null.
  final int? inventoryUnits;

  /// 1-based current step and total step count, e.g. 4 and 6.
  final int currentStep;
  final int totalSteps;

  /// Opens the item-details sheet ("Review item details" / "See item details").
  final VoidCallback? onReviewItemDetails;

  /// When true (phones) the card starts collapsed to a single header row and
  /// can be expanded; when false (wide layouts) it is always expanded.
  final bool collapsible;

  const SelectedRentalCard({
    super.key,
    required this.productName,
    required this.quantity,
    required this.totalLabel,
    required this.currentStep,
    required this.totalSteps,
    this.inventoryUnits,
    this.onReviewItemDetails,
    this.collapsible = false,
  });

  @override
  State<SelectedRentalCard> createState() => _SelectedRentalCardState();
}

class _SelectedRentalCardState extends State<SelectedRentalCard> {
  late bool _expanded = !widget.collapsible;

  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'YOUR SELECTED RENTAL',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.productName,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              if (widget.collapsible && !_expanded) ...[
                const SizedBox(height: 2),
                Text(
                  '${formatUnits(widget.quantity)} · ${widget.totalLabel}',
                  style: const TextStyle(fontSize: 12, color: AppColors.charcoal),
                ),
              ],
            ],
          ),
        ),
        if (widget.collapsible)
          Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: AppColors.charcoal),
      ],
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.collapsible
              ? InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(padding: const EdgeInsets.all(16), child: header),
                )
              : Padding(padding: const EdgeInsets.all(16), child: header),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  if (widget.inventoryUnits != null)
                    _row('Rental inventory', '${formatUnits(widget.inventoryUnits!)} total'),
                  _row('Quantity', formatUnits(widget.quantity)),
                  _row('Current total', widget.totalLabel),
                  _row('Included with rental', 'See item details', onTap: widget.onReviewItemDetails),
                  _row('Current step', '${widget.currentStep} of ${widget.totalSteps}'),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: widget.onReviewItemDetails,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Review item details',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.blush.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Secure booking flow', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        SizedBox(height: 4),
                        Text(
                          'Payment is completed manually via GCash before document submission.',
                          style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.charcoal),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {VoidCallback? onTap}) {
    final valueText = Text(
      value,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: onTap != null ? AppColors.primary : AppColors.textPrimary,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.charcoal)),
          const SizedBox(width: 12),
          Flexible(child: onTap == null ? valueText : InkWell(onTap: onTap, child: valueText)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Frame: hero + banner + stepper + (sidebar) + step card
// ---------------------------------------------------------------------------

class ReservationFrame extends StatelessWidget {
  static const wideBreakpoint = 900.0;
  static const maxContentWidth = 1120.0;

  final String? productName;
  final String? dailyRateLabel;

  /// Null hides the banner.
  final DateTime? savedAt;
  final bool progressRestored;

  /// Zero-based (0 = Rental Details ... 5 = Booking Confirmation).
  final int stepIndex;

  /// Shown at the right of the card header, e.g. "Verification Documents".
  final String stepTitle;

  /// Builds the "Your selected rental" card. Null omits the summary entirely
  /// (Step 2 shows its own summary inside the step). [collapsible] is true on
  /// phones.
  final Widget Function(bool collapsible)? summaryBuilder;

  final ScrollController? controller;
  final Widget child;

  const ReservationFrame({
    super.key,
    this.productName,
    this.dailyRateLabel,
    this.savedAt,
    this.progressRestored = false,
    required this.stepIndex,
    required this.stepTitle,
    this.summaryBuilder,
    this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= wideBreakpoint;
        final card = _StepCard(stepIndex: stepIndex, title: stepTitle, child: child);
        final builder = summaryBuilder;

        final Widget body;
        if (builder == null) {
          body = card;
        } else if (wide) {
          body = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 240, child: builder(false)),
              const SizedBox(width: 16),
              Expanded(child: card),
            ],
          );
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [builder(true), const SizedBox(height: 12), card],
          );
        }

        return SingleChildScrollView(
          controller: controller,
          padding: EdgeInsets.all(wide ? 24 : 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ReservationHero(productName: productName, dailyRateLabel: dailyRateLabel),
                  if (savedAt != null) ...[
                    const SizedBox(height: 12),
                    SavedProgressBanner(savedAt: savedAt!, restored: progressRestored),
                  ],
                  const SizedBox(height: 12),
                  ReservationStepper(currentIndex: stepIndex),
                  const SizedBox(height: 12),
                  body,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StepCard extends StatelessWidget {
  final int stepIndex;
  final String title;
  final Widget child;
  const _StepCard({required this.stepIndex, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STEP ${stepIndex + 1} OF ${ReservationStepper.labels.length}',
                style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned action bar
// ---------------------------------------------------------------------------

class ReservationActionBar extends StatelessWidget {
  /// Null hides the Back button (Step 1 has none).
  final String? backLabel;
  final VoidCallback? onBack;
  final String nextLabel;

  /// Null disables the primary button.
  final VoidCallback? onNext;
  final bool busy;

  const ReservationActionBar({
    super.key,
    this.backLabel,
    this.onBack,
    required this.nextLabel,
    this.onNext,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final next = ElevatedButton(
      style: ElevatedButton.styleFrom(
        disabledBackgroundColor: AppColors.lightGray,
        disabledForegroundColor: const Color(0xFF8A8A87),
      ),
      onPressed: (onNext != null && !busy) ? onNext : null,
      child: busy
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
            )
          : Text(nextLabel, textAlign: TextAlign.center),
    );
    final back = backLabel == null
        ? null
        : OutlinedButton(
            onPressed: busy ? null : onBack,
            child: Text(backLabel!),
          );

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          // heightFactor: 1 makes this shrink-wrap to the buttons' height. A bare
          // Center takes ALL the height it is offered, and Scaffold's
          // bottomNavigationBar slot offers the whole screen — so the bar used to
          // cover the entire page in white with the buttons floating in the middle.
          child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: ReservationFrame.maxContentWidth),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final roomy = constraints.maxWidth >= 600;
                  if (roomy) {
                    return Row(
                      children: [
                        if (back != null) back,
                        const Spacer(),
                        next,
                      ],
                    );
                  }
                  if (back == null) {
                    return SizedBox(width: double.infinity, child: next);
                  }
                  return Row(
                    children: [
                      back,
                      const SizedBox(width: 12),
                      Expanded(child: next),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}