// lib/screens/booking/booking_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
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
  bool _payingNow = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bookingFuture = widget.initialBooking != null
        ? Future.value(widget.initialBooking)
        : BookingService.getBookingById(widget.bookingId);
  }

  Future<void> _payNow(Booking booking) async {
    setState(() {
      _payingNow = true;
      _error = null;
    });
    try {
      final checkoutUrl = await BookingService.createPaymongoCheckoutSession(booking.id);
      final launched = await launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication);
      if (!launched) throw StateError('Could not open the payment page.');
      if (!mounted) return;
      context.push('/booking-payment-pending', extra: booking);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = describeBookingError(e));
    } finally {
      if (mounted) setState(() => _payingNow = false);
    }
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
    return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(b.productName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              BookingStatusChip(status: b.status),
            ],
          ),
          const SizedBox(height: 4),
          Text('Booking #${b.id.substring(0, 8).toUpperCase()}',
              style: const TextStyle(color: AppColors.charcoal, fontSize: 12)),
          const SizedBox(height: 20),
          _detailCard([
            _row('Dates', '${_fmt(b.startDate)} – ${_fmt(b.endDate)} (${b.nights} night(s))'),
            _row('Quantity', '${b.quantity} unit(s)'),
            _row('Daily rate', '${b.dailyRateSnapshot.toStringAsFixed(0)}'),
            _row('Refundable deposit', '${b.refundableDepositSnapshot.toStringAsFixed(0)}'),
            _row('Total', '${b.totalAmount.toStringAsFixed(0)}', emphasize: true),
            _row('Payment', b.isPaid ? 'Paid' : 'Unpaid'),
          ]),
          const SizedBox(height: 16),
          _detailCard([
            _row('Name', b.fullName),
            _row('Phone', b.phoneNumber),
            _row('Address', b.fullAddress),
            _row('ID type', b.idType),
          ]),
          if (b.adminNotes != null && b.adminNotes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _detailCard([_row('Note from Maddy & Cassy', b.adminNotes!)]),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppColors.statusRed)),
          ],
          if (!b.isPaid && b.status != BookingStatus.cancelled && b.status != BookingStatus.rejected) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _payingNow ? null : () => _payNow(b),
                child: _payingNow
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                    : const Text('Pay Now'),
              ),
            ),
          ],
          if (b.isCancellable) ...[
            const SizedBox(height: 12),
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