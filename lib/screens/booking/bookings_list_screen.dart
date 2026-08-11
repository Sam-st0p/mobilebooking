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
              return _ScrollableMessage(
                icon: Icons.error_outline,
                message: 'Could not load your bookings. Pull down to try again.',
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
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: bookings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _BookingCard(
                booking: bookings[i],
                onChanged: () => setState(_load),
              ),
            );
          },
        ),
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
                child: booking.productImage.isEmpty
                    ? Container(width: 64, height: 64, color: AppColors.lightGray)
                    : CachedNetworkImage(
                        imageUrl: booking.productImage,
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
                    Text(booking.productName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      '${_fmt(booking.startDate)} – ${_fmt(booking.endDate)} · ${booking.quantity} unit(s)',
                      style: const TextStyle(color: AppColors.charcoal, fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                    BookingStatusChip(status: booking.status),
                  ],
                ),
              ),
              Text('${booking.totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.month}/${d.day}';
}
