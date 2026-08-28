

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../models/booking.dart';
import '../../models/product.dart';
import '../../services/booking_service.dart';
import '../../services/product_service.dart';
import '../../theme/app_theme.dart';

class ReserveScreen extends StatefulWidget {
  final String idOrSlug;
  const ReserveScreen({super.key, required this.idOrSlug});

  @override
  State<ReserveScreen> createState() => _ReserveScreenState();
}

class _ReserveScreenState extends State<ReserveScreen> {
  late Future<Product?> _productFuture;

  @override
  void initState() {
    super.initState();
    _productFuture = ProductService.getProductById(widget.idOrSlug);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reserve')),
      body: FutureBuilder<Product?>(
        future: _productFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final product = snapshot.data;
          if (product == null) {
            return const Center(child: Text('This product could not be found.'));
          }
          if (product.availableUnits <= 0) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This item is fully booked right now — check back later.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          return _ReservationWizard(product: product);
        },
      ),
    );
  }
}

enum _Step { dates, fulfillment, review }

class _ReservationWizard extends StatefulWidget {
  final Product product;
  const _ReservationWizard({required this.product});

  @override
  State<_ReservationWizard> createState() => _ReservationWizardState();
}

class _ReservationWizardState extends State<_ReservationWizard> {
  _Step _step = _Step.dates;

  // --- Step 1: dates & quantity --------------------------------------
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime _focusedDay = DateTime.now();
  int _quantity = 1;
  bool _checkingAvailability = false;
  int? _availableForRange;
  String? _availabilityError;

  // --- Step 2: fulfillment ---------------------------------------------
  FulfillmentMethod _fulfillmentMethod = FulfillmentMethod.pickup;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _provinceController = TextEditingController();
  final _notesController = TextEditingController();

  // --- Step 3: review & submit ------------------------------------------
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int get _stepIndex => _Step.values.indexOf(_step);

  int get _nights =>
      (_startDate == null || _endDate == null) ? 0 : _endDate!.difference(_startDate!).inDays + 1;

  double get _subtotal => widget.product.dailyRate * _nights * _quantity;
  double get _depositTotal => widget.product.refundableDeposit * _quantity;
  // NOTE: delivery fee not yet part of the total shown here — see the
  // "to be confirmed" note in the review step instead of guessing a number.
  double get _total => _subtotal + _depositTotal;

  bool get _canProceed {
    switch (_step) {
      case _Step.dates:
        return _startDate != null &&
            _endDate != null &&
            !_checkingAvailability &&
            _availabilityError == null &&
            (_availableForRange ?? 0) >= _quantity;
      case _Step.fulfillment:
        final baseOk = _nameController.text.trim().isNotEmpty && _phoneController.text.trim().isNotEmpty;
        if (_fulfillmentMethod == FulfillmentMethod.pickup) return baseOk;
        return baseOk &&
            _addressController.text.trim().isNotEmpty &&
            _cityController.text.trim().isNotEmpty &&
            _provinceController.text.trim().isNotEmpty;
      case _Step.review:
        return true;
    }
  }

  Future<void> _onRangeSelected(DateTime? start, DateTime? end, DateTime focusedDay) async {
    setState(() {
      _startDate = start;
      _endDate = end;
      _focusedDay = focusedDay;
      _availableForRange = null;
      _availabilityError = null;
    });
    if (start == null || end == null) return;

    setState(() => _checkingAvailability = true);
    try {
      final result = await BookingService.checkAvailability(widget.product.id, start, end);
      if (!mounted) return;
      setState(() {
        _availableForRange = result.availableUnits;
        final maxQty = result.availableUnits == 0 ? 1 : result.availableUnits;
        _quantity = _quantity.clamp(1, maxQty).toInt();
        _checkingAvailability = false;
        _availabilityError = result.availableUnits <= 0 ? 'No units available for these dates.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkingAvailability = false;
        _availabilityError = 'Could not check availability. Please try again.';
      });
    }
  }

  void _goNext() {
    if (!_canProceed) return;
    if (_step == _Step.review) {
      _submit();
      return;
    }
    setState(() => _step = _Step.values[_stepIndex + 1]);
  }

  void _goBack() {
    if (_stepIndex == 0) {
      context.pop();
      return;
    }
    setState(() => _step = _Step.values[_stepIndex - 1]);
  }

  /// Inferred from the website's ALREADY-CONFIRMED customerSnapshot mapping
  /// (display_name/phone_number/full_address/contact_email — see project
  /// notes on ProfileService). Not confirmed against the RPC body itself —
  /// verify against src/services/bookingService.ts if available.
  Map<String, dynamic> _buildCustomerSnapshot() => {
        'display_name': _nameController.text.trim(),
        'phone_number': _phoneController.text.trim(),
        'full_address': _fulfillmentMethod == FulfillmentMethod.delivery
            ? _addressController.text.trim()
            : null,
      };

  /// Built from fields already available on the Product model used
  /// elsewhere in this file. Not confirmed against the RPC body — verify
  /// once website source is available.
  Map<String, dynamic> _buildProductSnapshot() => {
        'id': widget.product.id,
        'name': widget.product.name,
        'daily_rate': widget.product.dailyRate,
        'refundable_deposit': widget.product.refundableDeposit,
      };

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final method = _fulfillmentMethod == FulfillmentMethod.delivery ? 'delivery' : 'pickup';
      final location = _fulfillmentMethod == FulfillmentMethod.delivery
          ? _addressController.text.trim()
          : 'Store Pickup';

      final booking = await BookingService.createBooking(
        productId: widget.product.id,
        rentalStartDate: _startDate!,
        rentalEndDate: _endDate!,
        fulfillmentMethod: method,
        location: location,
        customerNotes: _notesController.text.trim(),
        // TODO: no known delivery fee schedule yet — defaulting to 0.
        // Surface the real fee here once the business rule is known.
        deliveryFee: 0,
        discountAmount: 0,
        productSnapshot: _buildProductSnapshot(),
        customerSnapshot: _buildCustomerSnapshot(),
        quantity: _quantity,
        cityMunicipality: _fulfillmentMethod == FulfillmentMethod.delivery
            ? _cityController.text.trim()
            : null,
        province:
            _fulfillmentMethod == FulfillmentMethod.delivery ? _provinceController.text.trim() : null,
      );

      if (!mounted) return;
      // No payment redirect here — real workflow requires admin approval,
      // then requirements + agreement completion, before payment. The
      // booking detail screen is where those next steps will surface once
      // stages 3-5 are built.
      context.pushReplacement('/account/bookings/${booking.id}', extra: booking);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Booking submitted! We'll notify you once it's reviewed."),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = describeBookingError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StepHeader(current: _stepIndex, total: _Step.values.length),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: switch (_step) {
              _Step.dates => _buildDatesStep(),
              _Step.fulfillment => _buildFulfillmentStep(),
              _Step.review => _buildReviewStep(),
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : _goBack,
                    child: Text(_stepIndex == 0 ? 'Cancel' : 'Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_canProceed && !_submitting) ? _goNext : null,
                    child: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                          )
                        : Text(_step == _Step.review ? 'Submit Booking' : 'Next'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Step builders --------------------------------------------------------

  Widget _buildDatesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Choose your dates'),
        const SizedBox(height: 4),
        const Text('Tap a start date, then an end date.',
            style: TextStyle(color: AppColors.charcoal, fontSize: 13)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.all(8),
          child: TableCalendar(
            firstDay: DateTime.now(),
            lastDay: DateTime.now().add(const Duration(days: 365)),
            focusedDay: _focusedDay,
            rangeStartDay: _startDate,
            rangeEndDay: _endDate,
            rangeSelectionMode: RangeSelectionMode.enforced,
            calendarFormat: CalendarFormat.month,
            onRangeSelected: (start, end, focused) => _onRangeSelected(start, end, focused),
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
            calendarStyle: const CalendarStyle(
              rangeHighlightColor: AppColors.calendarAvailableBg,
              rangeStartDecoration: BoxDecoration(color: AppColors.calendarSelected, shape: BoxShape.circle),
              rangeEndDecoration: BoxDecoration(color: AppColors.calendarSelected, shape: BoxShape.circle),
              todayDecoration: BoxDecoration(color: AppColors.blush, shape: BoxShape.circle),
              selectedDecoration: BoxDecoration(color: AppColors.calendarSelected, shape: BoxShape.circle),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_checkingAvailability)
          const Row(children: [
            SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Checking availability…', style: TextStyle(color: AppColors.charcoal)),
          ])
        else if (_availabilityError != null)
          Text(_availabilityError!, style: const TextStyle(color: AppColors.statusRed))
        else if (_availableForRange != null)
          Text('$_availableForRange unit(s) available for these dates.',
              style: const TextStyle(color: AppColors.statusGreen, fontWeight: FontWeight.w600)),
        if (_startDate != null && _endDate != null && (_availableForRange ?? 0) > 0) ...[
          const SizedBox(height: 20),
          _sectionTitle('Quantity'),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('$_quantity', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              IconButton.filledTonal(
                onPressed: _quantity < (_availableForRange ?? 1) ? () => setState(() => _quantity++) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _priceSummaryCard(),
        ],
      ],
    );
  }

  Widget _buildFulfillmentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('How will you get it?'),
        const SizedBox(height: 12),
        SegmentedButton<FulfillmentMethod>(
          segments: const [
            ButtonSegment(value: FulfillmentMethod.pickup, label: Text('Pickup'), icon: Icon(Icons.store_outlined)),
            ButtonSegment(
                value: FulfillmentMethod.delivery, label: Text('Delivery'), icon: Icon(Icons.local_shipping_outlined)),
          ],
          selected: {_fulfillmentMethod},
          onSelectionChanged: (s) => setState(() => _fulfillmentMethod = s.first),
        ),
        const SizedBox(height: 20),
        _sectionTitle('Contact details'),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Full name'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone number'),
          onChanged: (_) => setState(() {}),
        ),
        if (_fulfillmentMethod == FulfillmentMethod.delivery) ...[
          const SizedBox(height: 20),
          _sectionTitle('Delivery address'),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Street address'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cityController,
            decoration: const InputDecoration(labelText: 'City / Municipality'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _provinceController,
            decoration: const InputDecoration(labelText: 'Province'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Delivery fee will be confirmed by the team after booking.',
              style: TextStyle(color: AppColors.charcoal, fontSize: 12.5),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _sectionTitle('Notes (optional)'),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          maxLines: 2,
          decoration: const InputDecoration(hintText: 'Anything we should know?'),
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Review your booking'),
        const SizedBox(height: 16),
        _reviewRow('Item', widget.product.name),
        _reviewRow('Dates', '${_fmt(_startDate)} – ${_fmt(_endDate)} ($_nights night(s))'),
        _reviewRow('Quantity', '$_quantity'),
        _reviewRow('Fulfillment', _fulfillmentMethod == FulfillmentMethod.delivery ? 'Delivery' : 'Pickup'),
        _reviewRow('Name', _nameController.text.trim()),
        _reviewRow('Phone', _phoneController.text.trim()),
        if (_fulfillmentMethod == FulfillmentMethod.delivery) ...[
          _reviewRow('Address', _addressController.text.trim()),
          _reviewRow('City', _cityController.text.trim()),
          _reviewRow('Province', _provinceController.text.trim()),
        ],
        const SizedBox(height: 16),
        _priceSummaryCard(),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.blush.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: AppColors.charcoal),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "After you submit, Maddy & Cassy will review your booking. "
                  "Once approved, we'll ask you to complete ID verification "
                  'and sign the rental agreement before payment.',
                  style: TextStyle(color: AppColors.charcoal, fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        if (_submitError != null) ...[
          const SizedBox(height: 16),
          Text(_submitError!, style: const TextStyle(color: AppColors.statusRed)),
        ],
      ],
    );
  }

  // --- Shared bits ------------------------------------------------------

  Widget _sectionTitle(String text) =>
      Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700));

  Widget _reviewRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(label, style: const TextStyle(color: AppColors.charcoal))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Widget _priceSummaryCard() {
    final currency = widget.product.currency;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _priceRow('Daily rate × $_nights night(s) × $_quantity',
              '$currency${_subtotal.toStringAsFixed(0)}'),
          _priceRow('Refundable deposit × $_quantity', '$currency${_depositTotal.toStringAsFixed(0)}'),
          const Divider(height: 20),
          _priceRow('Estimated total', '$currency${_total.toStringAsFixed(0)}', emphasize: true),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value, {bool emphasize = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: emphasize ? AppColors.textPrimary : AppColors.charcoal,
                      fontWeight: emphasize ? FontWeight.w700 : FontWeight.normal)),
            ),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: emphasize ? 16 : 14,
                    color: emphasize ? AppColors.primary : AppColors.textPrimary)),
          ],
        ),
      );

  String _fmt(DateTime? d) => d == null ? '—' : '${d.month}/${d.day}/${d.year}';
}

class _StepHeader extends StatelessWidget {
  final int current;
  final int total;
  const _StepHeader({required this.current, required this.total});

  static const _labels = ['Dates', 'Fulfillment', 'Review'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step ${current + 1} of $total · ${_labels[current]}',
              style: const TextStyle(color: AppColors.charcoal, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: List.generate(total, (i) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= current ? AppColors.primary : AppColors.lightGray,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}