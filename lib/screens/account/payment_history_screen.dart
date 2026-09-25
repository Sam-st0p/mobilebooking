// lib/screens/account/payment_history_screen.dart
//
// Was previously a "Coming soon" placeholder — GET /account/payments did
// not exist on the backend at all. Now backed by PaymentHistoryController.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/payment_record.dart';
import '../../services/payment_history_service.dart';
import '../../theme/app_theme.dart';

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  late Future<List<PaymentRecord>> _paymentsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _paymentsFuture = PaymentHistoryService.getMyPayments();

  Future<void> _refresh() async {
    setState(_load);
    await _paymentsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment History')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<PaymentRecord>>(
          future: _paymentsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ScrollableMessage(
                icon: Icons.error_outline,
                message: 'Could not load your payment history. Pull down to try again.\n\n'
                    '${snapshot.error}',
              );
            }
            final payments = snapshot.data ?? [];
            if (payments.isEmpty) {
              return const _ScrollableMessage(
                icon: Icons.receipt_long_outlined,
                message: 'No payments yet. Once you submit a GCash payment for a booking, it will show up here.',
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: payments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _PaymentCard(
                payment: payments[index],
                onTap: () => context.push('/account/bookings/${payments[index].bookingId}'),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  final PaymentRecord payment;
  final VoidCallback onTap;
  const _PaymentCard({required this.payment, required this.onTap});

  Color get _statusColor => switch (payment.status) {
        'verified' => AppColors.statusGreen,
        'rejected' => AppColors.statusRed,
        _ => AppColors.primary, // submitted / under_review
      };

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: 'PHP', decimalDigits: 2);
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(payment.productName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          payment.bookingReference.isEmpty ? payment.bookingId : payment.bookingReference,
                          style: const TextStyle(fontSize: 12, color: AppColors.charcoal),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      payment.statusLabel,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _statusColor),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(payment.stageLabel, style: const TextStyle(fontSize: 12.5, color: AppColors.charcoal)),
                  Text(
                    currency.format(payment.amount),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    payment.referenceNumber.isEmpty ? '—' : 'Ref: ${payment.referenceNumber}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.charcoal),
                  ),
                  Text(
                    DateFormat('MMM d, y').format(payment.submittedAt),
                    style: const TextStyle(fontSize: 11.5, color: AppColors.charcoal),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrollableMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  const _ScrollableMessage({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 40, color: AppColors.charcoal),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.charcoal)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}