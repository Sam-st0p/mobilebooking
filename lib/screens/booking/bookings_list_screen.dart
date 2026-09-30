// lib/screens/booking/bookings_list_screen.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/booking.dart';
import '../../services/booking_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/booking_status_chip.dart';

class BookingsListScreen extends StatefulWidget {
  const BookingsListScreen({super.key});

  @override
  State<BookingsListScreen> createState() => _BookingsListScreenState();
}

class _BookingsListScreenState extends State<BookingsListScreen> {
  late Future<List<Booking>> _bookingsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _bookingsFuture = BookingService.getMyBookings();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _bookingsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Bookings')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Booking>>(
          future: _bookingsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final reason = describeBookingError(snapshot.error ?? '');
              return _ScrollableMessage(
                icon: Icons.error_outline,
                // Show the reason too (e.g. "You need to be signed in…"), not just a generic line.
                message: 'Could not load your bookings. Pull down to try again.\n\n$reason',
              );
            }
            final bookings = snapshot.data ?? [];
            if (bookings.isEmpty) {
              return _ScrollableMessage(
                icon: Icons.event_note_outlined,
                message: "You haven't made a booking yet.",
                actionLabel: 'Browse the catalog',
                onAction: () => context.go('/catalog'),
              );
            }
            // Index 0 is the status summary; bookings follow from index 1.
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: bookings.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => i == 0
                  ? _StatusSummary(bookings: bookings)
                  : _BookingCard(
                      booking: bookings[i - 1],
                      onChanged: () => setState(_load),
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// Which summary bucket a booking belongs to. Every status lands in exactly
/// one bucket, so the three counts always add up to the total.
enum _SummaryGroup { completed, pending, cancelled }

_SummaryGroup _groupFor(BookingStatus status) {
  switch (status) {
    case BookingStatus.returned:
      return _SummaryGroup.completed;
    case BookingStatus.cancelled:
    case BookingStatus.rejected:
      return _SummaryGroup.cancelled;
    case BookingStatus.draft:
    case BookingStatus.pending:
    case BookingStatus.approved:
    case BookingStatus.confirmed:
    case BookingStatus.readyForRelease:
    case BookingStatus.released:
      return _SummaryGroup.pending;
  }
}

/// Completed / Pending / Cancelled counts, computed from the loaded bookings
/// so they refresh whenever the list reloads (pull-to-refresh, cancel, etc).
class _StatusSummary extends StatelessWidget {
  final List<Booking> bookings;
  const _StatusSummary({required this.bookings});

  @override
  Widget build(BuildContext context) {
    int count(_SummaryGroup g) => bookings.where((b) => _groupFor(b.status) == g).length;

    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            label: 'Completed',
            count: count(_SummaryGroup.completed),
            fg: AppColors.statusGreen,
            bg: AppColors.statusGreenBg,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            label: 'Pending',
            count: count(_SummaryGroup.pending),
            fg: AppColors.statusYellow,
            bg: AppColors.statusYellowBg,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryTile(
            label: 'Cancelled',
            count: count(_SummaryGroup.cancelled),
            fg: AppColors.statusRed,
            bg: AppColors.statusRedBg,
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final int count;
  final Color fg;
  final Color bg;
  const _SummaryTile({required this.label, required this.count, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$count',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: fg)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ScrollableMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _ScrollableMessage({required this.icon, required this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 40, color: AppColors.charcoal),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.charcoal)),
        if (actionLabel != null) ...[
          const SizedBox(height: 16),
          Center(child: OutlinedButton(onPressed: onAction, child: Text(actionLabel!))),
        ],
      ],
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback onChanged;
  const _BookingCard({required this.booking, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/account/bookings/${booking.id}', extra: booking).then((_) => onChanged()),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: booking.primaryImageUrl.isEmpty
                    ? Container(width: 64, height: 64, color: AppColors.lightGray)
                    : CachedNetworkImage(
                        imageUrl: booking.primaryImageUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            Container(width: 64, height: 64, color: AppColors.lightGray),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(booking.primaryProductName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      '${_fmt(booking.pickupAt)} – ${_fmt(booking.returnAt)} · ${booking.totalQuantity} unit(s)',
                      style: const TextStyle(color: AppColors.charcoal, fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                    // NOTE: payment status badge removed here — payment now
                    // lives in booking_payment_submissions, not a field on
                    // bookings. Re-add once stage 5 (payment rebuild) gives
                    // us a way to fetch the latest submission per booking.
                    BookingStatusChip(status: booking.status),
                  ],
                ),
              ),
              Text(booking.totalAmount.toStringAsFixed(0),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.month}/${d.day}';
}