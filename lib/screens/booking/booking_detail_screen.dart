// lib/screens/booking/booking_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/booking.dart';
import '../../services/booking_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/booking_status_chip.dart';

class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  final Booking? initialBooking;
  const BookingDetailScreen({super.key, required this.bookingId, this.initialBooking});

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  late Future<Booking?> _bookingFuture;
  bool _cancelling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Always re-fetch rather than trusting `initialBooking` as-is: the list
    // screen's row doesn't include the same totals/fulfillment fields with
    // the same safety margin, and this keeps one code path for "fully
    // populated" bookings.
    _bookingFuture = BookingService.getBookingById(widget.bookingId);
  }

  Future<void> _cancel(Booking booking) async {
    final reasonController = TextEditingController();
    final detailsController = TextEditingController();

    // TEMPORARY: free-text reason entry. The real app uses a fixed dropdown
    // (CANCELLATION_REASON_OPTIONS in src/types/booking.ts) that the
    // backend RPC validates against — that exact list wasn't available
    // when this was written. Replace this with a real dropdown once it is;
    // until then, a mismatched reason fails safely with a clear server
    // error rather than silently succeeding with wrong data.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This sends a cancellation request for administrator review. '
                'Reserved dates remain held until it is approved.'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason to cancel'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: detailsController,
              decoration: const InputDecoration(labelText: 'Additional details (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep booking')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit request')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (reasonController.text.trim().isEmpty) return;

    setState(() {
      _cancelling = true;
      _error = null;
    });
    try {
      await BookingService.cancelBooking(
        booking.id,
        reason: reasonController.text.trim(),
        additionalDetails: detailsController.text.trim().isEmpty ? null : detailsController.text.trim(),
      );
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cancelling = false;
        _error = describeBookingError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Details'),
        // When this page is opened with context.go() (e.g. "Track Booking" after a
        // reservation) there is nothing to pop, so Flutter shows no back arrow and
        // the screen was a dead end. Offer a way back to My Bookings in that case;
        // when it can be popped, the normal back arrow appears as usual.
        leading: context.canPop()
            ? null
            : IconButton(
                tooltip: 'My Bookings',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/account/bookings'),
              ),
        actions: [
          IconButton(
            tooltip: 'Home',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => context.go('/'),
          ),
        ],
      ),
      body: FutureBuilder<Booking?>(
        future: _bookingFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final b = snapshot.data;
          if (b == null) {
            return const Center(child: Text('This booking could not be found.'));
          }
          return _buildBody(b);
        },
      ),
    );
  }

  Widget _buildBody(Booking b) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(b.primaryProductName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            BookingStatusChip(status: b.status),
          ],
        ),
        const SizedBox(height: 4),
        Text(b.bookingReference.isNotEmpty ? 'Booking #${b.bookingReference}' : 'Booking #${b.id.substring(0, 8).toUpperCase()}',
            style: const TextStyle(color: AppColors.charcoal, fontSize: 12)),
        const SizedBox(height: 20),
        _detailCard([
          _row('Dates', '${_fmt(b.pickupAt)} – ${_fmt(b.returnAt)} (${b.nights} night(s))'),
          _row('Quantity', '${b.totalQuantity} unit(s)'),
          for (final item in b.items)
            _row(item.productNameSnapshot,
                '${item.quantity} × ${item.dailyRateSnapshot.toStringAsFixed(0)}/day'),
          _row('Rental subtotal', b.rentalSubtotal.toStringAsFixed(0)),
          if (b.deliveryFee > 0) _row('Delivery fee', b.deliveryFee.toStringAsFixed(0)),
          if ((b.pickupConvenienceFee ?? 0) > 0)
            _row('Convenience fee', b.pickupConvenienceFee!.toStringAsFixed(0)),
          if (b.specialDiscountAmount > 0)
            _row('Discount', '-${b.specialDiscountAmount.toStringAsFixed(0)}'),
          if (b.refundableDeposit > 0)
            _row('Refundable deposit', b.refundableDeposit.toStringAsFixed(0)),
          _row('Total', b.totalAmount.toStringAsFixed(0), emphasize: true),
        ]),
        const SizedBox(height: 16),
        _detailCard([
          _row('Fulfillment', b.fulfillmentMethod == FulfillmentMethod.delivery ? 'Delivery' : 'Pickup'),
          if (b.fulfillmentMethod == FulfillmentMethod.delivery &&
              b.location != null &&
              b.location!.isNotEmpty)
            _row('Location', b.location!),
        ]),
        // NOTE: Identity/ID requirements (name, phone, address, ID type)
        // used to be shown here directly from the booking row. They now
        // live in booking_requirements + customer_documents (stage 3 —
        // not yet built). This section intentionally omitted rather than
        // showing stale/wrong data; re-add once that flow exists.
        //
        // NOTE: "Pay Now" button also removed — payment now goes through
        // booking_payment_submissions + a rebuilt Edge Function (stage 5),
        // not a simple isPaid check on the booking row.
        if (b.customerNotes != null && b.customerNotes!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _detailCard([_row('Your notes', b.customerNotes!)]),
        ],
        if (b.adminNotes != null && b.adminNotes!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _detailCard([_row('Note from Maddy & Cassy', b.adminNotes!)]),
        ],
        if (b.requirementsStatus == 'not_submitted' &&
            b.status != BookingStatus.cancelled &&
            b.status != BookingStatus.rejected) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () async {
                // Steps 4-6 of the guided reservation (documents, agreement,
                // confirmation). Refresh on return so the requirements
                // status reflects whatever was submitted.
                await context.push<bool>('/account/bookings/${b.id}/documents', extra: b);
                if (mounted) {
                  setState(() => _bookingFuture = BookingService.getBookingById(widget.bookingId));
                }
              },
              icon: const Icon(Icons.description_outlined),
              label: const Text('Complete Requirements'),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: AppColors.statusRed)),
        ],
        if (b.isCancellable) ...[
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _cancelling ? null : () => _cancel(b),
              child: _cancelling
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Cancel Booking'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _detailCard(List<Widget> children) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: children),
      );

  Widget _row(String label, String value, {bool emphasize = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        // The label column is normally 130 wide but shrinks on very narrow screens
        // instead of overflowing.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labelWidth = constraints.maxWidth * 0.4 < 130 ? constraints.maxWidth * 0.4 : 130.0;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: labelWidth, child: Text(label, style: const TextStyle(color: AppColors.charcoal))),
                Expanded(
                  child: Text(value,
                      style: TextStyle(
                          fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
                          color: emphasize ? AppColors.primary : AppColors.textPrimary)),
                ),
              ],
            );
          },
        ),
      );

  String _fmt(DateTime d) => '${d.month}/${d.day}/${d.year}';
}