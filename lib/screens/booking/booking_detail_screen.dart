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
    // screen's row doesn't include booking_totals in the same shape safety
    // margin, and this keeps one code path for "fully populated" bookings.
    _bookingFuture = BookingService.getBookingById(widget.bookingId);
  }

  Future<void> _cancel(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text('This cannot be undone. You can always book again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep booking')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel booking')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _cancelling = true;
      _error = null;
    });
    try {
      await BookingService.cancelBooking(booking.id);
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
      appBar: AppBar(title: const Text('Booking Details')),
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
    final fulfillment = b.fulfillment;
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
          if (b.totals != null) ...[
            _row('Rental subtotal', b.totals!.rentalSubtotal.toStringAsFixed(0)),
            if (b.totals!.deliveryFee > 0) _row('Delivery fee', b.totals!.deliveryFee.toStringAsFixed(0)),
            if (b.totals!.pickupConvenienceFee > 0)
              _row('Convenience fee', b.totals!.pickupConvenienceFee.toStringAsFixed(0)),
            if (b.totals!.specialDiscountTotal > 0)
              _row('Discount', '-${b.totals!.specialDiscountTotal.toStringAsFixed(0)}'),
            if (b.totals!.depositTotal > 0)
              _row('Refundable deposit', b.totals!.depositTotal.toStringAsFixed(0)),
            _row('Total', b.totalAmount.toStringAsFixed(0), emphasize: true),
          ],
        ]),
        if (fulfillment != null) ...[
          const SizedBox(height: 16),
          _detailCard([
            _row('Fulfillment', fulfillment.method == FulfillmentMethod.delivery ? 'Delivery' : 'Pickup'),
            if (fulfillment.method == FulfillmentMethod.delivery) ...[
              if (fulfillment.recipientName != null) _row('Recipient', fulfillment.recipientName!),
              if (fulfillment.addressLine1 != null) _row('Address', fulfillment.addressLine1!),
              if (fulfillment.cityMunicipality != null) _row('City', fulfillment.cityMunicipality!),
              if (fulfillment.province != null) _row('Province', fulfillment.province!),
              if (fulfillment.contactNumber != null) _row('Contact', fulfillment.contactNumber!),
            ],
          ]),
        ],
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: Text(label, style: const TextStyle(color: AppColors.charcoal))),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
                      color: emphasize ? AppColors.primary : AppColors.textPrimary)),
            ),
          ],
        ),
      );

  String _fmt(DateTime d) => '${d.month}/${d.day}/${d.year}';
}