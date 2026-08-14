// lib/screens/booking/reserve_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/product.dart';
import '../../services/booking_service.dart';
import '../../services/product_service.dart';
import '../../theme/app_theme.dart';

/// Port of the `app/catalog/[id]/reserve` multi-step flow (dates →
/// requirements → agreement → review), collapsed into one screen with an
/// internal step index rather than separate routes — simpler to keep in
/// sync as one wizard, and avoids losing state on the mobile back gesture
/// between steps. Payment itself happens on PayMongo's hosted checkout
/// page, opened right after submit — see PaymentPendingScreen.
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

enum _Step { dates, requirements, agreement, review }

const _idTypes = [
  "Driver's License",
  'Passport',
  'Philippine National ID (PhilSys)',
  'UMID',
  'Other government ID',
];

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

  // --- Step 2: requirements -------------------------------------------
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  String? _idType;
  Uint8List? _idPhotoBytes;
  String _idPhotoExt = 'jpg';

  // --- Step 3: agreement ------------------------------------------------
  bool _agreementAccepted = false;

  // --- Step 4: review & submit ------------------------------------------
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  int get _stepIndex => _Step.values.indexOf(_step);

  int get _nights =>
      (_startDate == null || _endDate == null) ? 0 : _endDate!.difference(_startDate!).inDays + 1;

  double get _subtotal => widget.product.dailyRate * _nights * _quantity;
  double get _depositTotal => widget.product.refundableDeposit * _quantity;
  double get _total => _subtotal + _depositTotal;

  bool get _canProceed {
    switch (_step) {
      case _Step.dates:
        return _startDate != null &&
            _endDate != null &&
            !_checkingAvailability &&
            _availabilityError == null &&
            (_availableForRange ?? 0) >= _quantity;
      case _Step.requirements:
        return _nameController.text.trim().isNotEmpty &&
            _phoneController.text.trim().isNotEmpty &&
            _addressController.text.trim().isNotEmpty &&
            _idType != null &&
            _idPhotoBytes != null;
      case _Step.agreement:
        return _agreementAccepted;
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

  Future<void> _pickIdPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';

    setState(() {
      _idPhotoBytes = bytes;
      _idPhotoExt = ext;
    });
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

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final idPhotoPath = await BookingService.uploadIdPhoto(_idPhotoBytes!, _idPhotoExt);

      final booking = await BookingService.createBooking(
        productId: widget.product.id,
        start: _startDate!,
        end: _endDate!,
        quantity: _quantity,
        fullName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        fullAddress: _addressController.text.trim(),
        idType: _idType!,
        idPhotoPath: idPhotoPath,
      );

      final checkoutUrl = await BookingService.createPaymongoCheckoutSession(booking.id);

      final launched = await launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication);
      if (!launched) {
        throw StateError('Could not open the payment page. Please try again.');
      }

      if (!mounted) return;
      context.pushReplacement('/booking-payment-pending', extra: booking);
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
              _Step.requirements => _buildRequirementsStep(),
              _Step.agreement => _buildAgreementStep(),
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
                        : Text(_step == _Step.review ? 'Continue to Payment' : 'Next'),
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

  Widget _buildRequirementsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Rental requirements'),
        const SizedBox(height: 4),
        const Text('We need this to confirm and prepare your booking.',
            style: TextStyle(color: AppColors.charcoal, fontSize: 13)),
        const SizedBox(height: 16),
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
        const SizedBox(height: 12),
        TextField(
          controller: _addressController,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Full address'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _idType,
          decoration: const InputDecoration(labelText: 'Valid ID type'),
          items: _idTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: (value) => setState(() => _idType = value),
        ),
        const SizedBox(height: 16),
        _sectionTitle('Photo of your valid ID'),
        const SizedBox(height: 8),
        _imagePickerTile(bytes: _idPhotoBytes, label: 'Upload ID photo', onTap: _pickIdPhoto),
      ],
    );
  }

  Widget _buildAgreementStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Rental agreement'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'By booking, you agree to: return the item(s) in the condition '
            'received, on or before the end date selected; that the '
            'refundable deposit may be withheld to cover loss, damage, or '
            'late return; and that Rental by Maddy & Cassy may verify the '
            'ID provided. See full Terms & Conditions for complete policies '
            'on cancellations, extensions, and liability.',
            style: TextStyle(color: AppColors.charcoal, height: 1.5),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.push('/terms'),
          child: const Text('Read full Terms & Conditions'),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _agreementAccepted,
          onChanged: (v) => setState(() => _agreementAccepted = v ?? false),
          title: const Text('I have read and agree to the Rental Agreement and Terms & Conditions.'),
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
        _reviewRow('Name on booking', _nameController.text.trim()),
        _reviewRow('Phone', _phoneController.text.trim()),
        _reviewRow('Address', _addressController.text.trim()),
        _reviewRow('ID type', _idType ?? '—'),
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
              Icon(Icons.lock_outline, size: 18, color: AppColors.charcoal),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "You'll be taken to PayMongo's secure checkout to pay via "
                  'GCash, card, or QRPh. Your booking stays Pending Review '
                  'until payment is confirmed.',
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
          _priceRow('Total due now', '$currency${_total.toStringAsFixed(0)}', emphasize: true),
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

  Widget _imagePickerTile({required Uint8List? bytes, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 140,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
          image: bytes != null ? DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover) : null,
        ),
        child: bytes == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_a_photo_outlined, color: AppColors.charcoal),
                  const SizedBox(height: 8),
                  Text(label, style: const TextStyle(color: AppColors.charcoal)),
                ],
              )
            : Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.white,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      icon: const Icon(Icons.edit, color: AppColors.primary),
                      onPressed: onTap,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  String _fmt(DateTime? d) => d == null ? '—' : '${d.month}/${d.day}/${d.year}';
}

class _StepHeader extends StatelessWidget {
  final int current;
  final int total;
  const _StepHeader({required this.current, required this.total});

  static const _labels = ['Dates', 'Requirements', 'Agreement', 'Review'];

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