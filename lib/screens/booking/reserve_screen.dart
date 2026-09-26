// lib/screens/booking/reserve_screen.dart
//
// Steps 1-3 of the guided reservation, laid out like the web app:
//   1 Rental Details -> 2 Reservation -> 3 Payment Submission
// Steps 4-6 (Verification Documents, Rental Agreement, Booking
// Confirmation) live in booking_documents_screen.dart; after payment is
// submitted this screen hands off to it, so the flow feels continuous.
//
// Progress saving: text fields and choices are saved on this device (never
// files) so a half-finished reservation survives leaving the screen. Once
// the booking has been created (leaving Step 2) its id is saved too, so
// coming back resumes at Payment instead of creating a duplicate booking.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../models/booking.dart';
import '../../models/product.dart';
import '../../services/availability_service.dart';
import '../../services/auth_provider.dart';
import '../../services/booking_service.dart';
import '../../services/draft_store.dart';
import '../../services/payment_service.dart';
import '../../services/product_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/ph_provinces.dart';
import '../../widgets/document_upload_tile.dart';
import '../../widgets/form_layout.dart';
import '../../widgets/reservation_chrome.dart';
import 'booking_documents_screen.dart';

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
    // Booking requires an account (POST /mobile/bookings answers 401 "You need
    // to be signed in to book." otherwise). Check up front instead of letting
    // people fill in two steps and fail at the end. Their progress is saved on
    // this device, so it is restored when they come back after signing in.
    final auth = context.watch<AppAuth>();
    if (auth.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reserve')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (auth.user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reserve')),
        body: const _SignInRequired(),
      );
    }

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

class _SignInRequired extends StatelessWidget {
  const _SignInRequired();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 40, color: AppColors.primary),
              const SizedBox(height: 16),
              const Text(
                'Sign in to reserve',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                "We'll email you a one-time code. Your booking history, payment receipts and "
                'documents live in your account. Anything you fill in is saved on this device, '
                'so you can pick up where you left off after signing in.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.charcoal),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.push('/sign-in'),
                  child: const Text('Sign in'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.push('/sign-up'),
                child: const Text('Create an account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Step { details, reservation, payment }

class _TableCell {
  final String label;
  final String value;
  final bool highlight;
  const _TableCell(this.label, this.value, {this.highlight = false});
}

class _ReservationWizard extends StatefulWidget {
  final Product product;
  const _ReservationWizard({required this.product});

  @override
  State<_ReservationWizard> createState() => _ReservationWizardState();
}

class _ReservationWizardState extends State<_ReservationWizard> {
  static const _gcashQrAsset = 'assets/images/gcash_qr.png';
  static const _gcashAccountName = 'NORMAN CONCEPCION';
  static const _gcashMobileNumber = '09562278409';

  _Step _step = _Step.details;
  final _scroll = ScrollController();

  // --- Step 1: rental details (customer info) ---------------------------
  // Confirmed required against src/services/bookingSubmissionService.ts::
  // validateReservationDetails — sent fresh with every booking, not reused
  // from the stored profile.
  final _customerFullNameController = TextEditingController();
  final _customerEmailController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerStreetController = TextEditingController();
  final _customerCityController = TextEditingController();
  final _customerFacebookController = TextEditingController();
  final _customerInstagramController = TextEditingController();
  String? _customerProvince;

  /// Fields the user has already visited — errors only show after blur.
  final Set<String> _touched = {};

  // --- Step 2: reservation (dates, time, fulfillment, quantity) ---------
  DateTime? _startDate;
  DateTime? _endDate; // null while only one calendar day is tapped
  DateTime _focusedDay = DateTime.now();
  int _quantity = 1;
  Map<String, DayAvailability> _calendar = {};
  bool _checkingAvailability = false;
  int? _availableForRange;
  String? _availabilityError;
  int _availabilityRequestId = 0;

  // Confirmed against src/lib/rentalTiming.ts. Time-of-day matters: a
  // 9:00 AM pickup and an 8:00 PM pickup on the same date are NOT
  // equivalent — the fee depends on it.
  int? _hour12; // 1..12, null until the customer picks a time
  int _minute = 0;
  String _period = 'AM';
  static const _normalPickupStartMinutes = 9 * 60;
  static const _normalPickupEndMinutes = 19 * 60;
  static const _pickupConvenienceFeeAmount = 100.0;

  FulfillmentMethod? _fulfillment;
  String? _selectedVariant;
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _provinceController = TextEditingController();
  final _notesController = TextEditingController();

  // --- Step 3: payment submission ---------------------------------------
  // The booking is created when leaving the Reservation step — Payment
  // submits against that real bookingId.
  bool _creatingBooking = false;
  String? _bookingCreationError;
  Booking? _createdBooking;

  String _paymentOption = 'deposit_50'; // "deposit_50" | "full"
  final _referenceNumberController = TextEditingController();
  final _accountNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  PickedDocument? _proof;
  bool _submittingPayment = false;
  String? _paymentError;

  late final Future<bool> _qrAvailable =
      rootBundle.load(_gcashQrAsset).then((_) => true, onError: (Object _) => false);

  // --- Draft persistence ---------------------------------------------------
  Timer? _saveDebounce;
  DateTime? _savedAt;
  bool _restored = false;
  bool _draftDisabled = false;

  @override
  void initState() {
    super.initState();
    // Prefill from the signed-in customer's saved profile FIRST, so a
    // returning customer doesn't retype their name/phone/links on every
    // booking. Runs before _restoreDraft() so an in-progress draft for this
    // specific product (if any) still wins over the generic profile default.
    _prefillFromProfile();
    _loadCalendar();
    _restoreDraft();
  }

  /// Fills Rental Details from the customer's profile where the two line up
  /// 1:1. Only Street/Barangay gets a value from `fullAddress`, since the
  /// profile stores address as one combined string while this form splits
  /// it into street/city/province — City and Province cannot be safely
  /// guessed from that string, so those stay blank for the customer to fill
  /// in themselves.
  void _prefillFromProfile() {
    final profile = context.read<AppAuth>().profile;
    if (profile == null) return;

    if (profile.displayName.trim().isNotEmpty) {
      _customerFullNameController.text = profile.displayName.trim();
    }
    if (profile.email.trim().isNotEmpty) {
      _customerEmailController.text = profile.email.trim();
    }
    if ((profile.phoneNumber ?? '').trim().isNotEmpty) {
      _customerPhoneController.text = profile.phoneNumber!.trim();
    }
    if ((profile.fullAddress ?? '').trim().isNotEmpty) {
      _customerStreetController.text = profile.fullAddress!.trim();
    }
    if ((profile.facebookLink ?? '').trim().isNotEmpty) {
      _customerFacebookController.text = profile.facebookLink!.trim();
    }
    if ((profile.instagramLink ?? '').trim().isNotEmpty) {
      _customerInstagramController.text = profile.instagramLink!.trim();
    }
  }

  @override
  void dispose() {
    if ((_saveDebounce?.isActive ?? false) && !_draftDisabled) {
      unawaited(_persistNow()); // values are snapshotted before controllers go
    }
    _saveDebounce?.cancel();
    _scroll.dispose();
    _customerFullNameController.dispose();
    _customerEmailController.dispose();
    _customerPhoneController.dispose();
    _customerStreetController.dispose();
    _customerCityController.dispose();
    _customerFacebookController.dispose();
    _customerInstagramController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _notesController.dispose();
    _referenceNumberController.dispose();
    _accountNameController.dispose();
    _accountNumberController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Derived values
  // ---------------------------------------------------------------------

  int get _stepIndex => _Step.values.indexOf(_step);
  bool get _locked => _createdBooking != null;
  String get _currency => widget.product.currency;

  String get _stepTitle {
    switch (_step) {
      case _Step.details:
        return 'Rental Details';
      case _Step.reservation:
        return 'Reservation';
      case _Step.payment:
        return 'Payment Submission';
    }
  }

  DateTime? get _effectiveEnd => _endDate ?? _startDate;

  /// Calendar day count, matching differenceInCalendarDays(end, start) + 1
  /// in StepRentalDetails.tsx.
  int get _rentalDays {
    final start = _startDate;
    final end = _effectiveEnd;
    if (start == null || end == null) return 1;
    return (end.difference(start).inDays + 1).clamp(1, 1000000).toInt();
  }

  /// "HH:mm" (24h) or null until an hour is chosen.
  String? get _pickupTime {
    final h = _hour12;
    if (h == null) return null;
    final hour24 = (h % 12) + (_period == 'PM' ? 12 : 0);
    return '${hour24.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';
  }

  String get _timeLabel {
    final h = _hour12;
    if (h == null) return 'No time selected';
    return '$h:${_minute.toString().padLeft(2, '0')} $_period';
  }

  void _setTime24(int hour24, int minute) {
    _hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    _minute = minute;
    _period = hour24 >= 12 ? 'PM' : 'AM';
  }

  bool get _isOutsidePickupWindow {
    final time = _pickupTime;
    if (time == null) return false;
    final parts = time.split(':');
    final minutes = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    return minutes < _normalPickupStartMinutes || minutes > _normalPickupEndMinutes;
  }

  double get _pickupConvenienceFee => _isOutsidePickupWindow ? _pickupConvenienceFeeAmount : 0;

  /// NOTE: uses local device time, not a hard Asia/Manila offset like the
  /// real combineManilaPickupDateTime — fine while the device is on
  /// Philippine time.
  DateTime? get _pickupAt {
    final start = _startDate;
    final time = _pickupTime;
    if (start == null || time == null) return null;
    final parts = time.split(':');
    return DateTime(start.year, start.month, start.day, int.parse(parts[0]), int.parse(parts[1]));
  }

  bool get _isPickupTimePast => _pickupAt != null && _pickupAt!.isBefore(DateTime.now());

  /// Return timestamp = pickup + 22h for the first day + 24h per extra day
  /// (RENTAL_DURATION_HOURS/TURNAROUND_HOURS rule from rentalTiming.ts).
  DateTime? get _returnAt {
    final pickup = _pickupAt;
    if (pickup == null) return null;
    return pickup.add(Duration(hours: 22 + (_rentalDays - 1) * 24));
  }

  double get _subtotal => widget.product.dailyRate * _rentalDays * _quantity;
  double get _depositTotal => widget.product.refundableDeposit * _quantity;
  // Catalog discount, birthday perk, loyalty reward and delivery fee are NOT
  // included — those come from the server (reservationPricing.ts).
  double get _total => _subtotal + _depositTotal + _pickupConvenienceFee;
  double get _dueNow => _paymentOption == 'deposit_50' ? (_total * 0.5) : _total;

  List<String> get _availableColors {
    final raw = widget.product.specifications['colors'] ?? widget.product.specifications['Color'] ?? '';
    return raw.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
  }

  int get _maxQuantity => (_availableForRange ?? widget.product.availableUnits).clamp(1, 1000).toInt();

  bool _isValidPhone(String v) => RegExp(r'^\d{11}$').hasMatch(v);
  bool _isValidEmail(String v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);

  bool get _canProceed {
    if (_locked && _step != _Step.payment) return true; // read-only steps
    switch (_step) {
      case _Step.details:
        return _customerFullNameController.text.trim().isNotEmpty &&
            _isValidEmail(_customerEmailController.text.trim()) &&
            _isValidPhone(_customerPhoneController.text.trim()) &&
            _customerStreetController.text.trim().isNotEmpty &&
            _customerCityController.text.trim().isNotEmpty &&
            _customerProvince != null &&
            _customerFacebookController.text.trim().isNotEmpty &&
            _customerInstagramController.text.trim().isNotEmpty;
      case _Step.reservation:
        final hasValidVariant = _availableColors.isEmpty || _selectedVariant != null;
        final hasValidLocation = _fulfillment == FulfillmentMethod.pickup ||
            (_fulfillment == FulfillmentMethod.delivery &&
                _addressController.text.trim().isNotEmpty &&
                _cityController.text.trim().isNotEmpty &&
                _provinceController.text.trim().isNotEmpty);
        return _startDate != null &&
            _pickupAt != null &&
            !_isPickupTimePast &&
            hasValidVariant &&
            hasValidLocation &&
            !_checkingAvailability &&
            _availabilityError == null &&
            (_availableForRange ?? 0) >= _quantity;
      case _Step.payment:
        return _referenceNumberController.text.trim().isNotEmpty &&
            _accountNameController.text.trim().isNotEmpty &&
            _isValidPhone(_accountNumberController.text.trim()) &&
            _proof != null &&
            !_submittingPayment;
    }
  }

  // ---------------------------------------------------------------------
  // Draft persistence
  // ---------------------------------------------------------------------

  String get _draftKey => 'reservation_draft_v1_${widget.product.id}';

  bool get _hasDraftContent =>
      _createdBooking != null ||
      _startDate != null ||
      _hour12 != null ||
      _fulfillment != null ||
      _customerProvince != null ||
      [
        _customerFullNameController,
        _customerEmailController,
        _customerPhoneController,
        _customerStreetController,
        _customerCityController,
        _customerFacebookController,
        _customerInstagramController,
      ].any((c) => c.text.trim().isNotEmpty);

  Map<String, dynamic> _draftValues() => {
        'step': _stepIndex,
        'fullName': _customerFullNameController.text,
        'email': _customerEmailController.text,
        'phone': _customerPhoneController.text,
        'street': _customerStreetController.text,
        'city': _customerCityController.text,
        'province': _customerProvince,
        'facebook': _customerFacebookController.text,
        'instagram': _customerInstagramController.text,
        'startDate': _startDate == null ? null : AvailabilityService.toDateKey(_startDate!),
        'endDate': _endDate == null ? null : AvailabilityService.toDateKey(_endDate!),
        'hour12': _hour12,
        'minute': _minute,
        'period': _period,
        'fulfillment': _fulfillment?.name,
        'address': _addressController.text,
        'deliveryCity': _cityController.text,
        'deliveryProvince': _provinceController.text,
        'notes': _notesController.text,
        'quantity': _quantity,
        'variant': _selectedVariant,
        'paymentOption': _paymentOption,
        'createdBookingId': _createdBooking?.id,
      };

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 700), _persistNow);
  }

  Future<void> _persistNow() async {
    if (_draftDisabled || !_hasDraftContent) return;
    final values = _draftValues(); // snapshot synchronously
    final savedAt = await DraftStore.save(_draftKey, values);
    if (!mounted || savedAt == null) return;
    setState(() {
      _savedAt = savedAt;
      _restored = false;
    });
  }

  Future<void> _clearDraft() async {
    _draftDisabled = true;
    _saveDebounce?.cancel();
    await DraftStore.clear(_draftKey);
  }

  DateTime? _parseDay(dynamic raw) {
    if (raw is! String) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  Future<void> _restoreDraft() async {
    final snapshot = await DraftStore.load(_draftKey);
    if (snapshot == null || !mounted) return;
    final v = snapshot.values;
    String text(String key) => (v[key] as String?) ?? '';

    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    var start = _parseDay(v['startDate']);
    var end = _parseDay(v['endDate']);
    if (start != null && start.isBefore(today)) {
      start = null; // that date has passed — make them pick again
      end = null;
    }

    final province = v['province'] as String?;
    final method = v['fulfillment'] as String?;
    final hour12 = v['hour12'] as int?;

    setState(() {
      _customerFullNameController.text = text('fullName');
      _customerEmailController.text = text('email');
      _customerPhoneController.text = text('phone');
      _customerStreetController.text = text('street');
      _customerCityController.text = text('city');
      _customerFacebookController.text = text('facebook');
      _customerInstagramController.text = text('instagram');
      _customerProvince = (province != null && kPhilippineProvinces.contains(province)) ? province : null;

      _startDate = start;
      _endDate = end;
      _focusedDay = start ?? _focusedDay;
      if (hour12 != null && hour12 >= 1 && hour12 <= 12) {
        _hour12 = hour12;
        _minute = (v['minute'] as int?) ?? 0;
        _period = v['period'] == 'PM' ? 'PM' : 'AM';
      }
      _fulfillment = method == 'delivery'
          ? FulfillmentMethod.delivery
          : (method == 'pickup' ? FulfillmentMethod.pickup : null);
      _addressController.text = text('address');
      _cityController.text = text('deliveryCity');
      _provinceController.text = text('deliveryProvince');
      _notesController.text = text('notes');
      _quantity = ((v['quantity'] as int?) ?? 1).clamp(1, 1000).toInt();
      _selectedVariant = v['variant'] as String?;
      _paymentOption = v['paymentOption'] == 'full' ? 'full' : 'deposit_50';

      _savedAt = snapshot.savedAt;
      _restored = true;
    });

    if (start != null) _checkAvailability();

    // Resume a booking that was already created (so we never create a duplicate).
    final bookingId = v['createdBookingId'] as String?;
    var resumedBooking = false;
    if (bookingId != null) {
      try {
        final booking = await BookingService.getBookingById(bookingId);
        if (!mounted) return;
        if (booking != null &&
            booking.status != BookingStatus.cancelled &&
            booking.status != BookingStatus.rejected) {
          setState(() => _createdBooking = booking);
          resumedBooking = true;
        }
      } catch (_) {
        // Fall through — they'll simply start at the beginning.
      }
    }

    final savedStep = ((v['step'] as int?) ?? 0).clamp(0, _Step.values.length - 1).toInt();
    final target = _Step.values[savedStep];
    if (!mounted) return;
    setState(() {
      _step = (target == _Step.payment && !resumedBooking) ? _Step.reservation : target;
    });
  }

  // ---------------------------------------------------------------------
  // Availability
  // ---------------------------------------------------------------------

  Future<void> _loadCalendar() async {
    final today = DateTime.now();
    try {
      final days = await AvailabilityService.getCalendar(
        widget.product.id,
        today,
        today.add(const Duration(days: 365)),
      );
      if (!mounted) return;
      setState(() => _calendar = days);
    } catch (_) {
      // The colour-coding is decoration; the real check happens per range.
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
    _scheduleSave();
    if (start == null) return;
    await _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    final start = _startDate;
    final end = _effectiveEnd;
    if (start == null || end == null) return;

    final requestId = ++_availabilityRequestId;
    setState(() {
      _checkingAvailability = true;
      _availabilityError = null;
    });
    try {
      final result = await BookingService.checkAvailability(widget.product.id, start, end, quantity: _quantity);
      if (!mounted || requestId != _availabilityRequestId) return;
      setState(() {
        _availableForRange = result.availableUnits;
        final maxQty = result.availableUnits == 0 ? 1 : result.availableUnits;
        _quantity = _quantity.clamp(1, maxQty).toInt();
        _checkingAvailability = false;
        _availabilityError = result.availableUnits <= 0 ? 'No units are available for these dates.' : null;
      });
    } catch (e) {
      if (!mounted || requestId != _availabilityRequestId) return;
      setState(() {
        _checkingAvailability = false;
        _availabilityError = 'Could not check availability. Please try again.';
      });
    }
  }

  // ---------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------

  void _setStep(_Step step) {
    setState(() => _step = step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_persistNow());
  }

  void _onChanged() {
    setState(() {});
    _scheduleSave();
  }

  void _goNext() {
    if (!_canProceed) return;
    if (_step == _Step.reservation && !_locked) {
      _createBookingAndAdvance();
      return;
    }
    if (_step == _Step.payment) {
      _submitPayment();
      return;
    }
    _setStep(_Step.values[_stepIndex + 1]);
  }

  void _goBack() {
    if (_stepIndex == 0) {
      context.pop();
      return;
    }
    _setStep(_Step.values[_stepIndex - 1]);
  }

  /// Creates the real booking when leaving the Reservation step, then
  /// advances to Payment.
  Future<void> _createBookingAndAdvance() async {
    final pickupAt = _pickupAt;
    final fulfillment = _fulfillment;
    final province = _customerProvince;
    if (pickupAt == null || fulfillment == null || province == null) return;

    setState(() {
      _creatingBooking = true;
      _bookingCreationError = null;
    });
    try {
      final isDelivery = fulfillment == FulfillmentMethod.delivery;
      final booking = await BookingService.createBooking(
        productId: widget.product.id,
        rentalStartDate: pickupAt,
        rentalDays: _rentalDays,
        fulfillmentMethod: isDelivery ? 'delivery' : 'pickup',
        customerFullName: _customerFullNameController.text.trim(),
        customerEmail: _customerEmailController.text.trim(),
        customerPhone: _customerPhoneController.text.trim(),
        customerStreetBarangay: _customerStreetController.text.trim(),
        customerCityMunicipality: _customerCityController.text.trim(),
        customerProvince: province,
        customerFacebookLink: _customerFacebookController.text.trim(),
        customerInstagramLink: _customerInstagramController.text.trim(),
        // Pickup never carries a delivery address.
        location: isDelivery ? _addressController.text.trim() : null,
        customerNotes: _notesController.text.trim(),
        quantity: _quantity,
        cityMunicipality: isDelivery ? _cityController.text.trim() : null,
        province: isDelivery ? _provinceController.text.trim() : null,
        variant: _selectedVariant,
      );

      if (!mounted) return;
      setState(() {
        _createdBooking = booking;
        _creatingBooking = false;
      });
      _setStep(_Step.payment);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creatingBooking = false;
        _bookingCreationError = describeBookingError(e);
      });
    }
  }

  Future<void> _submitPayment() async {
    final booking = _createdBooking;
    final proof = _proof;
    if (booking == null || proof == null) return;

    setState(() {
      _submittingPayment = true;
      _paymentError = null;
    });
    try {
      await PaymentService.submitPayment(
        bookingId: booking.id,
        declaredAmount: _dueNow,
        referenceNumber: _referenceNumberController.text.trim(),
        accountName: _accountNameController.text.trim(),
        accountNumber: _accountNumberController.text.trim(),
        proofBytes: proof.bytes,
        proofFilename: proof.filename,
        proofMimeType: proof.mimeType,
      );

      await _clearDraft();
      if (!mounted) return;
      // Continue straight into Step 4 (Verification Documents).
      context.pushReplacement(
        '/account/bookings/${booking.id}/documents',
        extra: BookingDocumentsArgs(booking: booking, customerName: _customerFullNameController.text.trim()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment submitted! Our team will verify it shortly.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submittingPayment = false;
        _paymentError = describeBookingError(e);
      });
    }
  }

  void _showItemDetails() {
    final product = widget.product;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.white,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Item details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text(product.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${formatMoney(_currency, product.dailyRate)} per day',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.charcoal),
                ),
                if (product.included.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Included with rental',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                  const SizedBox(height: 4),
                  for (final item in product.included)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  ', style: TextStyle(color: AppColors.charcoal)),
                          Expanded(
                            child: Text(item, style: const TextStyle(fontSize: 12.5, color: AppColors.charcoal)),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final busy = _creatingBooking || _submittingPayment;
    final product = widget.product;

    return Column(
      children: [
        Expanded(
          child: ReservationFrame(
            productName: product.name,
            dailyRateLabel: formatMoney(_currency, product.dailyRate),
            savedAt: _savedAt,
            progressRestored: _restored,
            stepIndex: _stepIndex,
            stepTitle: _stepTitle,
            controller: _scroll,
            // Step 2 shows its own "Review & booking summary" instead.
            summaryBuilder: _step == _Step.reservation
                ? null
                : (collapsible) => SelectedRentalCard(
                      productName: product.name,
                      quantity: _quantity,
                      totalLabel: _startDate == null ? 'Choose dates' : formatMoney(_currency, _total),
                      inventoryUnits: product.totalUnits,
                      currentStep: _stepIndex + 1,
                      totalSteps: 6,
                      onReviewItemDetails: _showItemDetails,
                      collapsible: collapsible,
                    ),
            child: switch (_step) {
              _Step.details => _lockable(_buildDetailsStep()),
              _Step.reservation => _lockable(_buildReservationStep()),
              _Step.payment => _buildPaymentStep(),
            },
          ),
        ),
        ReservationActionBar(
          backLabel: _stepIndex == 0 ? null : 'Back',
          onBack: _goBack,
          nextLabel: _step == _Step.payment ? 'Submit Payment & Continue' : 'Continue',
          onNext: _canProceed ? _goNext : null,
          busy: busy,
        ),
      ],
    );
  }

  /// Once the booking exists, Steps 1-2 are read-only: editing them would
  /// silently not change the booking that was already created.
  Widget _lockable(Widget child) {
    if (!_locked) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NoticeBox(
          child: Text(
            'Your booking has already been created, so these details are locked. To change them, '
            'cancel the booking from My Bookings and start a new reservation.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.charcoal),
          ),
        ),
        const SizedBox(height: 16),
        AbsorbPointer(child: Opacity(opacity: 0.6, child: child)),
      ],
    );
  }

  Widget _stepIntro(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 19, height: 1.25, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.charcoal)),
        const SizedBox(height: 18),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Step 1 — Rental Details
  // ---------------------------------------------------------------------

  Widget _blurTracked(String key, Widget child) => Focus(
        onFocusChange: (hasFocus) {
          if (!hasFocus) setState(() => _touched.add(key));
        },
        child: child,
      );

  Widget _buildDetailsStep() {
    final phone = _customerPhoneController.text.trim();
    final phoneInvalid = _touched.contains('phone') && phone.isNotEmpty && !_isValidPhone(phone);
    final email = _customerEmailController.text.trim();
    final emailInvalid = _touched.contains('email') && email.isNotEmpty && !_isValidEmail(email);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepIntro(
          'Rental Details',
          'Confirm the renter information that will appear on this reservation, invoice, receipt, and rental agreement.',
        ),
        FieldGrid(
          wideColumns: 2,
          children: [
            LabeledField(
              label: 'Full name',
              child: TextField(
                controller: _customerFullNameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _onChanged(),
              ),
            ),
            LabeledField(
              label: 'Email address',
              child: _blurTracked(
                'email',
                TextField(
                  controller: _customerEmailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(errorText: emailInvalid ? 'Enter a valid email address.' : null),
                  onChanged: (_) => _onChanged(),
                ),
              ),
            ),
            LabeledField(
              label: 'Active phone number',
              note: 'Use exactly 11 digits.',
              noteColor: phoneInvalid ? AppColors.statusRed : AppColors.charcoal,
              child: _blurTracked(
                'phone',
                TextField(
                  controller: _customerPhoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                  decoration: const InputDecoration(hintText: '09XXXXXXXXX'),
                  onChanged: (_) => _onChanged(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Street / Barangay',
          child: TextField(
            controller: _customerStreetController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'House/unit number, street, subdivision, and barangay'),
            onChanged: (_) => _onChanged(),
          ),
        ),
        const SizedBox(height: 16),
        FieldGrid(
          wideColumns: 2,
          children: [
            LabeledField(
              label: 'City / Municipality',
              child: TextField(
                controller: _customerCityController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'e.g. Manila'),
                onChanged: (_) => _onChanged(),
              ),
            ),
            LabeledField(
              label: 'Province',
              child: _dropdown<String>(
                value: _customerProvince,
                options: kPhilippineProvinces,
                hint: 'Select province',
                textOf: (p) => p,
                onChanged: (p) {
                  setState(() => _customerProvince = p);
                  _scheduleSave();
                },
              ),
            ),
            LabeledField(
              label: 'Facebook profile link',
              child: TextField(
                controller: _customerFacebookController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'https://facebook.com/yourprofile'),
                onChanged: (_) => _onChanged(),
              ),
            ),
            LabeledField(
              label: 'Instagram profile link',
              child: TextField(
                controller: _customerInstagramController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(hintText: 'https://instagram.com/yourprofile'),
                onChanged: (_) => _onChanged(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// A themed dropdown built from InputDecorator so it matches text fields.
  Widget _dropdown<T>({
    required T? value,
    required List<T> options,
    required String Function(T) textOf,
    required ValueChanged<T?>? onChanged,
    String? hint,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        fillColor: onChanged == null ? AppColors.background : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          menuMaxHeight: 320,
          hint: hint == null ? null : Text(hint, style: const TextStyle(color: AppColors.charcoal, fontSize: 14)),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          items: [
            for (final option in options) DropdownMenuItem<T>(value: option, child: Text(textOf(option))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Step 2 — Reservation
  // ---------------------------------------------------------------------

  Widget _buildReservationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepIntro('Reservation', "Pick your dates, choose a time, and let us know how you'd like to get your rental."),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 860;
            final middle = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _timePanel(),
                const SizedBox(height: 12),
                _fulfillmentPanel(),
                if (_availableColors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _variantPanel(),
                ],
                const SizedBox(height: 12),
                _quantityPanel(),
              ],
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: _calendarPanel()),
                  const SizedBox(width: 12),
                  Expanded(flex: 6, child: middle),
                  const SizedBox(width: 12),
                  Expanded(flex: 4, child: _reviewSummaryPanel()),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _calendarPanel(),
                const SizedBox(height: 12),
                middle,
                const SizedBox(height: 12),
                _reviewSummaryPanel(),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        SectionPanel(
          title: 'Notes (optional)',
          child: TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Anything we should know?'),
            onChanged: (_) => _scheduleSave(),
          ),
        ),
        if (_bookingCreationError != null) ...[
          const SizedBox(height: 12),
          Text(_bookingCreationError!, style: const TextStyle(color: AppColors.statusRed)),
        ],
      ],
    );
  }

  // --- 1. Calendar -----------------------------------------------------

  Widget _calendarPanel() {
    final now = DateTime.now();
    final firstDay = DateTime.utc(now.year, now.month, now.day);
    final lastDay = firstDay.add(const Duration(days: 365));

    return SectionPanel(
      title: '1. Choose your dates',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select one date, or select a start and end date for a multi-day rental.',
            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.charcoal),
          ),
          const SizedBox(height: 8),
          TableCalendar(
            firstDay: firstDay,
            lastDay: lastDay,
            focusedDay: _focusedDay.isBefore(firstDay) ? firstDay : _focusedDay,
            rangeStartDay: _startDate,
            rangeEndDay: _endDate,
            rangeSelectionMode: RangeSelectionMode.enforced,
            calendarFormat: CalendarFormat.month,
            availableGestures: AvailableGestures.horizontalSwipe,
            rowHeight: 40,
            daysOfWeekHeight: 24,
            enabledDayPredicate: (day) {
              final info = _calendar[AvailabilityService.toDateKey(day)];
              return info == null || !info.isBooked;
            },
            onRangeSelected: (start, end, focused) => _onRangeSelected(start, end, focused),
            onPageChanged: (focused) => _focusedDay = focused,
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            daysOfWeekStyle: const DaysOfWeekStyle(
              weekdayStyle: TextStyle(fontSize: 11, color: AppColors.charcoal),
              weekendStyle: TextStyle(fontSize: 11, color: AppColors.charcoal),
            ),
            calendarStyle: const CalendarStyle(
              outsideDaysVisible: false,
              rangeHighlightColor: Colors.transparent,
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focused) => _dayCell(day),
              todayBuilder: (context, day, focused) => _dayCell(day, isToday: true),
              disabledBuilder: (context, day, focused) => _dayCell(day),
              rangeStartBuilder: (context, day, focused) => _dayCell(day, selected: true),
              rangeEndBuilder: (context, day, focused) => _dayCell(day, selected: true),
              withinRangeBuilder: (context, day, focused) => _dayCell(day, inRange: true),
            ),
          ),
          const SizedBox(height: 4),
          if (_checkingAvailability)
            const Row(
              children: [
                SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Checking availability…', style: TextStyle(fontSize: 12, color: AppColors.charcoal)),
              ],
            )
          else if (_availabilityError != null)
            Text(_availabilityError!, style: const TextStyle(fontSize: 12, color: AppColors.statusRed))
          else if (_availableForRange != null)
            Text(
              '${formatUnits(_availableForRange!)} available for these dates.',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.statusGreen),
            )
          else
            const Text(
              'Select an available date from the calendar.',
              style: TextStyle(fontSize: 12, color: AppColors.charcoal),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _legendItem(AppColors.calendarAvailable, 'Available'),
              _legendItem(AppColors.calendarBooked, 'Booked · pending review'),
              _legendItem(AppColors.charcoal, 'Booked · confirmed'),
              _legendItem(AppColors.calendarSelected, 'Selected'),
              _legendItem(const Color(0xFFD0D0CC), 'Past'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day, {bool selected = false, bool inRange = false, bool isToday = false}) {
    final now = DateTime.now();
    final isPast = DateTime(day.year, day.month, day.day).isBefore(DateTime(now.year, now.month, now.day));
    final info = _calendar[AvailabilityService.toDateKey(day)];

    Color? background;
    var foreground = AppColors.textPrimary;
    TextDecoration? decoration;

    if (selected) {
      background = AppColors.calendarSelected;
      foreground = AppColors.white;
    } else if (inRange) {
      background = AppColors.calendarSelected.withValues(alpha: 0.22);
      foreground = AppColors.calendarSelected;
    } else if (isPast) {
      foreground = const Color(0xFFB8B8B4);
    } else if (info != null && info.isBooked) {
      if (info.isBookedConfirmed) {
        background = AppColors.charcoal.withValues(alpha: 0.14);
        foreground = AppColors.charcoal;
      } else {
        background = AppColors.calendarBookedBg;
        foreground = AppColors.calendarBooked;
      }
      decoration = TextDecoration.lineThrough;
    } else if (info != null) {
      background = AppColors.calendarAvailableBg;
      foreground = AppColors.calendarAvailable;
    }

    return Container(
      margin: const EdgeInsets.all(2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: (isToday && background == null) ? Border.all(color: AppColors.primary, width: 1.2) : null,
      ),
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: foreground,
          decoration: decoration,
          decorationColor: foreground,
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.charcoal)),
      ],
    );
  }

  // --- 2. Time -----------------------------------------------------------

  Widget _timePanel() {
    final time = _pickupTime;
    final scheduleReady = _startDate != null && time != null && !_isPickupTimePast;

    return SectionPanel(
      title: '2. Choose pickup or delivery time',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.blush.withValues(alpha: 0.14),
              border: Border.all(color: AppColors.dustyRose.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.blush.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.access_time, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CHOOSE YOUR TIME',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 0.9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.charcoal,
                            ),
                          ),
                          Text(_timeLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _miniLabeled(
                        'Hour',
                        _dropdown<int>(
                          value: _hour12,
                          options: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
                          hint: '--',
                          textOf: (h) => '$h',
                          onChanged: (h) {
                            setState(() => _hour12 = h);
                            _scheduleSave();
                          },
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(6, 0, 6, 12),
                      child: Text(':', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      flex: 3,
                      child: _miniLabeled(
                        'Minute',
                        _dropdown<int>(
                          value: _hour12 == null ? null : _minute,
                          options: const [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55],
                          hint: '00',
                          textOf: (m) => m.toString().padLeft(2, '0'),
                          onChanged: _hour12 == null
                              ? null
                              : (m) {
                                  setState(() => _minute = m ?? 0);
                                  _scheduleSave();
                                },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: _miniLabeled(
                        'Period',
                        _dropdown<String>(
                          value: _period,
                          options: const ['AM', 'PM'],
                          textOf: (p) => p,
                          onChanged: _hour12 == null
                              ? null
                              : (p) {
                                  setState(() => _period = p ?? 'AM');
                                  _scheduleSave();
                                },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Quick select', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in const [(9, 0), (12, 0), (15, 0), (18, 0), (19, 0)])
                      _quickTimeChip(t.$1, t.$2),
                  ],
                ),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 11, height: 1.4, color: AppColors.charcoal),
                    children: [
                      const TextSpan(text: 'Standard service window: '),
                      const TextSpan(text: '9:00 AM–7:00 PM', style: TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(
                        text: '. You may choose any future time; before 9:00 AM or after 7:00 PM adds '
                            '₱${_pickupConvenienceFeeAmount.toStringAsFixed(0)}.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isPickupTimePast) ...[
            const SizedBox(height: 8),
            const Text(
              'This time has already passed for the selected date. Pick a future time or a later date.',
              style: TextStyle(color: AppColors.statusRed, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          NoticeBox(
            fillAlpha: 0.16,
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scheduleReady ? 'Your schedule' : 'Select both a date and time',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        scheduleReady
                            ? '${_fulfillment == FulfillmentMethod.delivery ? 'Delivery' : 'Pickup'} on '
                                '${DateFormat('MMM d, y').format(_pickupAt!)} at $_timeLabel. '
                                'Return by ${DateFormat('MMM d, y, h:mm a').format(_returnAt!)}.'
                            : 'Your exact pickup or delivery schedule will appear here before you continue.',
                        style: const TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.charcoal),
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

  Widget _miniLabeled(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.charcoal)),
          const SizedBox(height: 4),
          child,
        ],
      );

  Widget _quickTimeChip(int hour24, int minute) {
    final label = DateFormat('h:mm a').format(DateTime(2000, 1, 1, hour24, minute));
    final selected = _pickupTime ==
        '${hour24.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: selected ? AppColors.white : AppColors.textPrimary)),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.white,
      side: const BorderSide(color: AppColors.border),
      shape: const StadiumBorder(),
      onSelected: (_) {
        setState(() => _setTime24(hour24, minute));
        _scheduleSave();
      },
    );
  }

  // --- 3. Pickup or delivery --------------------------------------------

  Widget _fulfillmentPanel() {
    return SectionPanel(
      title: '3. Pickup or delivery',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('How would you like to get your rental?'),
          const SizedBox(height: 8),
          FieldGrid(
            wideColumns: 2,
            breakpoint: 400,
            gap: 10,
            children: [
              ChoiceCard(
                selected: _fulfillment == FulfillmentMethod.pickup,
                title: 'Pickup',
                description:
                    'Right Focus Off Campus, Manuel Hizon, Sta. Cruz, Manila. Available by appointment from 9:00 AM to 7:00 PM.',
                onTap: () {
                  setState(() => _fulfillment = FulfillmentMethod.pickup);
                  _scheduleSave();
                },
              ),
              ChoiceCard(
                selected: _fulfillment == FulfillmentMethod.delivery,
                title: 'Delivery',
                description:
                    'Delivery is arranged manually by the business. Delivery fees and courier arrangements are '
                    'handled directly with you, outside this website.',
                onTap: () {
                  setState(() => _fulfillment = FulfillmentMethod.delivery);
                  _scheduleSave();
                },
              ),
            ],
          ),
          if (_fulfillment == FulfillmentMethod.delivery) ...[
            const SizedBox(height: 14),
            const Text(
              "We'll use the name and contact details from Rental Details for this delivery.",
              style: TextStyle(fontSize: 12, color: AppColors.charcoal),
            ),
            const SizedBox(height: 12),
            LabeledField(
              label: 'Delivery street address',
              child: TextField(
                controller: _addressController,
                maxLines: 2,
                onChanged: (_) => _onChanged(),
              ),
            ),
            const SizedBox(height: 12),
            FieldGrid(
              wideColumns: 2,
              breakpoint: 400,
              children: [
                LabeledField(
                  label: 'City / Municipality',
                  child: TextField(controller: _cityController, onChanged: (_) => _onChanged()),
                ),
                LabeledField(
                  label: 'Province',
                  child: TextField(controller: _provinceController, onChanged: (_) => _onChanged()),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // --- Color / variant (only shown for products that have colors) -------

  Widget _variantPanel() {
    return SectionPanel(
      title: 'Choose a color',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final color in _availableColors)
            ChoiceChip(
              label: Text(color, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              selected: _selectedVariant == color,
              onSelected: (_) {
                setState(() => _selectedVariant = color);
                _scheduleSave();
              },
            ),
        ],
      ),
    );
  }

  // --- 4. Quantity -------------------------------------------------------

  Widget _quantityPanel() {
    return SectionPanel(
      title: '4. Quantity',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.blush.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('How many do you need?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${formatUnits(widget.product.totalUnits)} in inventory',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.charcoal),
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.6)),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Decrease quantity',
                    visualDensity: VisualDensity.compact,
                    onPressed: _quantity > 1
                        ? () {
                            setState(() => _quantity--);
                            _scheduleSave();
                          }
                        : null,
                    icon: const Icon(Icons.remove, size: 18),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '$_quantity',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Increase quantity',
                    visualDensity: VisualDensity.compact,
                    onPressed: _quantity < _maxQuantity
                        ? () {
                            setState(() => _quantity++);
                            _scheduleSave();
                          }
                        : null,
                    icon: const Icon(Icons.add, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 5. Review & booking summary ----------------------------------------

  Widget _reviewSummaryPanel() {
    final start = _startDate;
    final end = _effectiveEnd;
    final needed = <String>[
      if (start == null) 'Choose your rental dates.',
      if (_pickupTime == null) 'Choose a pickup or delivery time.',
      if (_fulfillment == null) 'Choose pickup or delivery.',
      if (_availableColors.isNotEmpty && _selectedVariant == null) 'Choose a color.',
    ];

    String datesLabel = 'Not selected yet';
    if (start != null && end != null) {
      datesLabel = start == end || _rentalDays == 1
          ? DateFormat('MMM d, y').format(start)
          : '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, y').format(end)}';
    }

    return SectionPanel(
      color: AppColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '5. REVIEW & BOOKING SUMMARY',
            style: TextStyle(fontSize: 10.5, letterSpacing: 0.9, fontWeight: FontWeight.w700, color: AppColors.primary),
          ),
          const SizedBox(height: 6),
          Text(widget.product.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const Divider(height: 20),
          _summaryRow('Selected dates', datesLabel),
          _summaryRow('Pickup/delivery time', _pickupTime == null ? 'Not selected yet' : _timeLabel),
          _summaryRow(
            'Return time',
            _returnAt == null ? 'Not selected yet' : DateFormat('MMM d, h:mm a').format(_returnAt!),
          ),
          _summaryRow('Quantity', formatUnits(_quantity)),
          _summaryRow(
            'Pickup/Delivery',
            _fulfillment == null
                ? 'Not selected yet'
                : (_fulfillment == FulfillmentMethod.delivery ? 'Delivery' : 'Pickup'),
          ),
          if (_pickupConvenienceFee > 0)
            _summaryRow('Outside-hours fee', formatMoney(_currency, _pickupConvenienceFee)),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Current total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Flexible(
                child: Text(
                  start == null ? 'Choose dates' : formatMoney(_currency, _total),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primary),
                ),
              ),
            ],
          ),
          if (needed.isNotEmpty) ...[
            const SizedBox(height: 12),
            NoticeBox(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Still needed:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  for (final item in needed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  ', style: TextStyle(fontSize: 12)),
                          Expanded(child: Text(item, style: const TextStyle(fontSize: 12, height: 1.35))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.charcoal)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );

  // ---------------------------------------------------------------------
  // Step 3 — Payment Submission
  // ---------------------------------------------------------------------

  Widget _buildPaymentStep() {
    final currency = _currency;
    final balance = (_total - _dueNow).clamp(0, double.infinity).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepIntro(
          'Payment Submission',
          'Choose how much to pay now, then pay manually via GCash and submit your proof of payment below.',
        ),
        NoticeBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Your selected rental dates are secured once our team verifies your submitted payment.',
                style: TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              Text(
                'Paying 50% guarantees the reservation while leaving the remaining balance visible in your '
                'account. The reservation payment and listed deposit are non-refundable. Paying in full '
                'settles the online booking amount immediately.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.charcoal),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _sectionHeading('Choose a payment option'),
        const SizedBox(height: 8),
        FieldGrid(
          wideColumns: 2,
          breakpoint: 480,
          gap: 12,
          children: [
            ChoiceCard(
              selected: _paymentOption == 'deposit_50',
              title: 'Pay 50% to reserve',
              description: '${formatMoneyExact(currency, _total * 0.5)} due now',
              onTap: () {
                setState(() => _paymentOption = 'deposit_50');
                _scheduleSave();
              },
            ),
            ChoiceCard(
              selected: _paymentOption == 'full',
              title: 'Pay in full',
              description: '${formatMoneyExact(currency, _total)} due now',
              onTap: () {
                setState(() => _paymentOption = 'full');
                _scheduleSave();
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        _sectionHeading('Pay via GCash'),
        const SizedBox(height: 8),
        _gcashCard(currency),
        const SizedBox(height: 20),
        _sectionHeading('Payment Summary'),
        const SizedBox(height: 8),
        _paymentSummaryTable([
          _TableCell(
            'Product subtotal ($_quantity × $_rentalDays ${_rentalDays == 1 ? 'day' : 'days'})',
            formatMoneyExact(currency, _subtotal),
          ),
          _TableCell('Rental subtotal', formatMoneyExact(currency, _subtotal)),
          _TableCell('Non-refundable deposit', formatMoneyExact(currency, _depositTotal)),
          if (_pickupConvenienceFee > 0)
            _TableCell('Outside-hours fee', formatMoneyExact(currency, _pickupConvenienceFee)),
          const _TableCell('Online fees', 'Free'),
          _TableCell('Final amount', formatMoneyExact(currency, _total), highlight: true),
          _TableCell('Amount due now', formatMoneyExact(currency, _dueNow)),
          _TableCell('Balance after payment', formatMoneyExact(currency, balance)),
        ]),
        const SizedBox(height: 6),
        const Text(
          'Delivery courier costs are arranged separately with the business and are not part of this online payment.',
          style: TextStyle(fontSize: 11, color: AppColors.charcoal),
        ),
        const SizedBox(height: 20),
        _sectionHeading('Proof of Payment'),
        const SizedBox(height: 12),
        FieldGrid(
          wideColumns: 2,
          children: [
            LabeledField(
              label: 'Reference number',
              child: TextField(
                controller: _referenceNumberController,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
            ),
            LabeledField(
              label: 'Name of account used',
              child: TextField(
                controller: _accountNameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: '11-digit GCash mobile number used',
          child: TextField(
            controller: _accountNumberController,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Screenshot / proof of payment',
          child: DocumentUploadTile(
            semanticLabel: 'Screenshot / proof of payment',
            allowedExtensions: kPaymentProofExtensions,
            maxBytes: kMaxPaymentProofBytes,
            value: _proof,
            onChanged: (v) => setState(() => _proof = v),
          ),
        ),
        if (_paymentError != null) ...[
          const SizedBox(height: 16),
          Text(_paymentError!, style: const TextStyle(color: AppColors.statusRed)),
        ],
      ],
    );
  }

  Widget _sectionHeading(String text) =>
      Text(text, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800));

  Widget _gcashCard(String currency) {
    return FutureBuilder<bool>(
      future: _qrAvailable,
      builder: (context, snapshot) {
        final hasQr = snapshot.data == true;

        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _eyebrow('ACCOUNT NAME'),
            const SizedBox(height: 2),
            const Text(_gcashAccountName, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            _eyebrow('MOBILE NUMBER'),
            const SizedBox(height: 2),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                const Text(_gcashMobileNumber, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 36),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: _gcashMobileNumber));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Number copied')));
                  },
                  child: const Text('Copy number'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _eyebrow('ACCEPTED PAYMENT OPTIONS'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final option in const ['GCash', 'GCash to GCash', 'GCash to Bank']) _chip(option),
              ],
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 12, height: 1.45, color: AppColors.charcoal),
                children: [
                  const TextSpan(text: 'Send your '),
                  TextSpan(
                    text: formatMoneyExact(currency, _dueNow),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                  const TextSpan(
                    text: ' amount due now to the GCash account above, then fill out your proof of payment '
                        'below so we can verify your reservation.',
                  ),
                ],
              ),
            ),
          ],
        );

        return NoticeBox(
          fillAlpha: 0.22,
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 560;
              if (!hasQr) return details;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _qrBlock(),
                    const SizedBox(width: 16),
                    Expanded(child: details),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: _qrBlock()),
                  const SizedBox(height: 16),
                  details,
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _qrBlock() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _showQrFullScreen,
          child: Container(
            width: 168,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.asset(_gcashQrAsset, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 6),
        const Text('Scan with your GCash app', style: TextStyle(fontSize: 11, color: AppColors.charcoal)),
        const Text('Tap to enlarge', style: TextStyle(fontSize: 10.5, color: AppColors.primary)),
      ],
    );
  }

  void _showQrFullScreen() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.white,
        insetPadding: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: InteractiveViewer(child: Image.asset(_gcashQrAsset, fit: BoxFit.contain))),
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eyebrow(String text) => Text(
        text,
        style: const TextStyle(fontSize: 10, letterSpacing: 0.9, fontWeight: FontWeight.w700, color: AppColors.charcoal),
      );

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.blush.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
      );

  Widget _paymentSummaryTable(List<_TableCell> cells) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 3 : 2;
        final rows = <Widget>[];
        for (var i = 0; i < cells.length; i += columns) {
          final slice = cells.skip(i).take(columns).toList();
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < columns; j++) ...[
                    if (j > 0) const VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
                    Expanded(child: j < slice.length ? _tableCell(slice[j]) : const SizedBox.shrink()),
                  ],
                ],
              ),
            ),
          );
          if (i + columns < cells.length) {
            rows.add(const Divider(height: 1, thickness: 1, color: AppColors.border));
          }
        }
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: rows),
        );
      },
    );
  }

  Widget _tableCell(_TableCell cell) {
    return Container(
      color: cell.highlight ? AppColors.blush.withValues(alpha: 0.25) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(cell.label, style: const TextStyle(fontSize: 11, color: AppColors.charcoal)),
          const SizedBox(height: 4),
          Text(
            cell.value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: cell.highlight ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}