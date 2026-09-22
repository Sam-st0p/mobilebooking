// lib/screens/booking/booking_documents_screen.dart
//
// Steps 4-6 of the guided reservation:
//   4 Verification Documents -> 5 Rental Agreement -> 6 Booking Confirmation
//
// Nothing is saved to the server until "Sign & Submit Agreement" — confirmed
// against BookingDocumentController, which combines Step 4 and Step 5 into a
// single uploadDocument()×5 + submitDocuments() flow. Step 4's "Continue"
// only moves local state forward.
//
// Reached either straight from payment (reserve_screen.dart) or from
// "Complete Requirements" on the booking detail screen, via the route
// /account/bookings/:id/documents.
//
// Draft persistence: the *text* fields of Step 4 are saved on this device
// (per booking) so a half-finished form survives leaving the screen. Files
// and signature images are never stored.
//
// NOT implemented: reusing previously-approved documents (see
// documents_service.dart). Every submission uploads fresh files.

import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/booking.dart';
import '../../services/auth_provider.dart';
import '../../services/booking_service.dart';
import '../../services/documents_service.dart';
import '../../services/draft_store.dart';
import '../../services/product_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/document_upload_tile.dart';
import '../../widgets/form_layout.dart';
import '../../widgets/reservation_chrome.dart';
import '../../widgets/signature_pad.dart';

/// Passed as `extra` when navigating to /account/bookings/:id/documents.
class BookingDocumentsArgs {
  final Booking booking;

  /// The name typed in Rental Details, shown on the agreement. Falls back to
  /// the signed-in profile's display name when null.
  final String? customerName;

  const BookingDocumentsArgs({required this.booking, this.customerName});
}

enum _DocStep { documents, agreement, confirmation }

class BookingDocumentsScreen extends StatefulWidget {
  final String bookingId;

  /// Optional — pass the booking you already have to avoid a refetch.
  final Booking? booking;
  final String? customerName;

  const BookingDocumentsScreen({super.key, required this.bookingId, this.booking, this.customerName});

  @override
  State<BookingDocumentsScreen> createState() => _BookingDocumentsScreenState();
}

class _BookingDocumentsScreenState extends State<BookingDocumentsScreen> {
  _DocStep _step = _DocStep.documents;
  final _scroll = ScrollController();
  final _agreementScroll = ScrollController();

  // Summary / agreement data.
  Booking? _booking;
  int? _inventoryUnits;

  // --- Step 4: Verification Documents -----------------------------------
  PickedDocument? _idOne;
  PickedDocument? _idTwo;
  PickedDocument? _selfie;
  PickedDocument? _emergencyId;

  final _facebookController = TextEditingController();
  final _instagramController = TextEditingController();
  final _emergencyFullNameController = TextEditingController();
  final _emergencyRelationshipController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _emergencyFacebookController = TextEditingController();

  /// Fields already visited — errors only appear after a field loses focus.
  final Set<String> _touched = {};

  // --- Draft persistence (text fields only) -------------------------------
  Timer? _saveDebounce;
  DateTime? _savedAt;
  bool _restored = false;
  bool _draftDisabled = false;

  // --- Step 5: Rental Agreement -------------------------------------------
  // The web app shows TWO checkboxes, each of whose text explicitly covers
  // three of the six acknowledgement keys the backend requires:
  //   "Information & privacy"       -> infoAccurate, readPrivacyNotice,
  //                                   emergencyContactAuthorized
  //   "Rental terms & signature"   -> agreedToTerms, understoodRentalRules,
  //                                   authorizedESignature
  bool _confirmInfoPrivacy = false;
  bool _confirmTermsSignature = false;
  final _typedFullNameController = TextEditingController();
  String _signatureMethod = 'drawn'; // "drawn" | "uploaded"
  final _signaturePadKey = GlobalKey<SignaturePadState>();
  PickedDocument? _uploadedSignature;

  bool _submitting = false;
  String? _error;
  String? _uploadStatus;

  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
    _privacyTap = TapGestureRecognizer()..onTap = () => context.push('/privacy');
    _loadBooking();
    _restoreDraft();
  }

  @override
  void dispose() {
    if ((_saveDebounce?.isActive ?? false) && !_draftDisabled) {
      unawaited(_saveDraft()); // values are snapshotted before controllers go
    }
    _saveDebounce?.cancel();
    _privacyTap.dispose();
    _scroll.dispose();
    _agreementScroll.dispose();
    _facebookController.dispose();
    _instagramController.dispose();
    _emergencyFullNameController.dispose();
    _emergencyRelationshipController.dispose();
    _emergencyPhoneController.dispose();
    _emergencyFacebookController.dispose();
    _typedFullNameController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------

  Future<void> _loadBooking() async {
    Booking? loaded = _booking;
    if (loaded == null) {
      try {
        loaded = await BookingService.getBookingById(widget.bookingId);
      } catch (_) {
        return;
      }
      if (!mounted || loaded == null) return;
      final fetched = loaded;
      setState(() => _booking = fetched);
    }

    if (loaded.items.isEmpty) return;
    final productId = loaded.items.first.productId;
    if (productId.isEmpty) return;
    try {
      final product = await ProductService.getProductById(productId);
      if (!mounted || product == null) return;
      final units = product.totalUnits;
      setState(() => _inventoryUnits = units);
    } catch (_) {
      // "Rental inventory" row is simply omitted.
    }
  }

  String get _customerName {
    final fromWidget = widget.customerName;
    if (fromWidget != null && fromWidget.trim().isNotEmpty) return fromWidget.trim();
    try {
      final name = context.read<AppAuth>().profile?.displayName;
      if (name != null && name.trim().isNotEmpty) return name.trim();
    } catch (_) {}
    return '—';
  }

  String get _bookingRef {
    final booking = _booking;
    if (booking != null && booking.bookingReference.isNotEmpty) return booking.bookingReference;
    final id = widget.bookingId;
    return 'BK-${(id.length >= 8 ? id.substring(0, 8) : id).toUpperCase()}';
  }

  // ---------------------------------------------------------------------
  // Draft persistence
  // ---------------------------------------------------------------------

  String get _draftKey => 'booking_docs_draft_v2_${widget.bookingId}';

  Map<String, dynamic> _draftValues() => {
        'facebook': _facebookController.text,
        'instagram': _instagramController.text,
        'emergencyFullName': _emergencyFullNameController.text,
        'emergencyRelationship': _emergencyRelationshipController.text,
        'emergencyPhone': _emergencyPhoneController.text,
        'emergencyFacebook': _emergencyFacebookController.text,
      };

  Future<void> _restoreDraft() async {
    final snapshot = await DraftStore.load(_draftKey);
    if (snapshot == null || !mounted) return;
    final v = snapshot.values;
    String field(String key) => (v[key] as String?) ?? '';
    if (v.values.every((value) => (value as String? ?? '').trim().isEmpty)) return;

    setState(() {
      _facebookController.text = field('facebook');
      _instagramController.text = field('instagram');
      _emergencyFullNameController.text = field('emergencyFullName');
      _emergencyRelationshipController.text = field('emergencyRelationship');
      _emergencyPhoneController.text = field('emergencyPhone');
      _emergencyFacebookController.text = field('emergencyFacebook');
      _savedAt = snapshot.savedAt;
      _restored = true;
    });
  }

  void _scheduleDraftSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 700), _saveDraft);
  }

  Future<void> _saveDraft() async {
    if (_draftDisabled) return;
    final values = _draftValues(); // snapshot synchronously (see dispose)
    if (values.values.every((value) => (value as String).trim().isEmpty)) {
      await DraftStore.clear(_draftKey);
      return;
    }
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

  // ---------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------

  bool _isValidPhone(String v) => RegExp(r'^\d{11}$').hasMatch(v);

  /// Returns a full https:// URL, or null if [raw] isn't a usable link.
  /// The backend validates facebookLink/instagramLink with Laravel's `url`
  /// rule, so catching bad input here avoids a confusing failure at the very
  /// end of Step 5. A bare "facebook.com/me" is accepted and gets https://.
  String? _normalizeLink(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.contains(RegExp(r'\s'))) return null;
    final withScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(value) ? value : 'https://$value';
    final uri = Uri.tryParse(withScheme);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.userInfo.isNotEmpty) return null;
    if (uri.host.isEmpty || !uri.host.contains('.')) return null;
    return withScheme;
  }

  bool get _canProceedDocuments =>
      _idOne != null &&
      _idTwo != null &&
      _selfie != null &&
      _normalizeLink(_facebookController.text) != null &&
      _normalizeLink(_instagramController.text) != null &&
      _emergencyFullNameController.text.trim().isNotEmpty &&
      _emergencyRelationshipController.text.trim().isNotEmpty &&
      _isValidPhone(_emergencyPhoneController.text.trim()) &&
      _normalizeLink(_emergencyFacebookController.text) != null &&
      _emergencyId != null;

  bool get _hasSignature =>
      _signatureMethod == 'drawn' ? !(_signaturePadKey.currentState?.isEmpty ?? true) : _uploadedSignature != null;

  bool get _canSubmitAgreement =>
      _booking != null &&
      _confirmInfoPrivacy &&
      _confirmTermsSignature &&
      _typedFullNameController.text.trim().isNotEmpty &&
      _hasSignature &&
      !_submitting;

  void _onFieldChanged() {
    setState(() {});
    _scheduleDraftSave();
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  void _setStep(_DocStep step) {
    setState(() => _step = step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _onBack() {
    switch (_step) {
      case _DocStep.documents:
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/account/bookings/${widget.bookingId}');
        }
      case _DocStep.agreement:
        _setStep(_DocStep.documents);
      case _DocStep.confirmation:
        _goToBookings();
    }
  }

  void _onContinue() {
    switch (_step) {
      case _DocStep.documents:
        if (_canProceedDocuments) _setStep(_DocStep.agreement);
      case _DocStep.agreement:
        if (_canSubmitAgreement) _submit();
      case _DocStep.confirmation:
        context.go('/account/bookings/${widget.bookingId}');
    }
  }

  void _goToBookings() => context.go('/account/bookings');

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
      _uploadStatus = 'Preparing your files…';
    });
    try {
      final idOne = _idOne;
      final idTwo = _idTwo;
      final selfie = _selfie;
      final emergencyId = _emergencyId;
      if (idOne == null || idTwo == null || selfie == null || emergencyId == null) {
        throw Exception('Please go back and add all required documents.');
      }

      final facebookLink = _normalizeLink(_facebookController.text);
      final instagramLink = _normalizeLink(_instagramController.text);
      final emergencyFacebookLink = _normalizeLink(_emergencyFacebookController.text);
      if (facebookLink == null || instagramLink == null || emergencyFacebookLink == null) {
        throw Exception('Please go back and check your profile links.');
      }

      DocumentUpload signatureUpload;
      if (_signatureMethod == 'drawn') {
        final drawn = await _signaturePadKey.currentState?.capture();
        if (drawn == null) {
          throw Exception('Please draw your signature before submitting.');
        }
        signatureUpload = DocumentUpload(bytes: drawn, filename: 'signature.png', mimeType: 'image/png');
      } else {
        final uploaded = _uploadedSignature;
        if (uploaded == null) {
          throw Exception('Please upload a signature image before submitting.');
        }
        signatureUpload =
            DocumentUpload(bytes: uploaded.bytes, filename: uploaded.filename, mimeType: uploaded.mimeType);
      }

      final submissionId = DocumentsService.generateSubmissionId();

      DocumentUpload toUpload(PickedDocument d) =>
          DocumentUpload(bytes: d.bytes, filename: d.filename, mimeType: d.mimeType);

      // Upload ONE AT A TIME. The dev server (php artisan serve) handles a single
      // request at a time and every upload runs several slow database queries, so
      // firing all five at once made the last ones queue past the client timeout.
      final uploads = <String, DocumentUpload>{
        'idOne': toUpload(idOne),
        'idTwo': toUpload(idTwo),
        'selfie': toUpload(selfie),
        'emergencyId': toUpload(emergencyId),
        'signature': signatureUpload,
      };
      final uploadedPaths = <String, String>{};
      var done = 0;
      for (final entry in uploads.entries) {
        if (mounted) setState(() => _uploadStatus = 'Uploading file ${done + 1} of ${uploads.length}…');
        uploadedPaths[entry.key] = await DocumentsService.uploadDocument(
          bookingId: widget.bookingId,
          kind: entry.key,
          submissionId: submissionId,
          file: entry.value,
        );
        done++;
      }
      if (mounted) setState(() => _uploadStatus = 'Submitting your agreement…');

      await DocumentsService.submitDocuments(
        bookingId: widget.bookingId,
        submissionId: submissionId,
        files: uploadedPaths,
        facebookLink: facebookLink,
        instagramLink: instagramLink,
        emergencyFullName: _emergencyFullNameController.text.trim(),
        emergencyRelationship: _emergencyRelationshipController.text.trim(),
        emergencyPhone: _emergencyPhoneController.text.trim(),
        emergencyFacebookLink: emergencyFacebookLink,
        acknowledgements: {
          'infoAccurate': _confirmInfoPrivacy,
          'readPrivacyNotice': _confirmInfoPrivacy,
          'emergencyContactAuthorized': _confirmInfoPrivacy,
          'agreedToTerms': _confirmTermsSignature,
          'understoodRentalRules': _confirmTermsSignature,
          'authorizedESignature': _confirmTermsSignature,
        },
        signatureMethod: _signatureMethod,
        typedFullName: _typedFullNameController.text.trim(),
      );

      await _clearDraft();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _uploadStatus = null;
        _savedAt = null;
      });
      _setStep(_DocStep.confirmation);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _uploadStatus = null;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _showItemDetails() {
    final booking = _booking;
    if (booking == null) return;

    final currency = booking.productSnapshot.currency;
    final lines = booking.items.isNotEmpty
        ? [
            for (final i in booking.items)
              (name: i.productNameSnapshot, qty: i.quantity, rate: i.dailyRateSnapshot, included: i.included),
          ]
        : [
            (
              name: booking.productSnapshot.name,
              qty: booking.quantity,
              rate: booking.productSnapshot.pricePerDay,
              included: booking.productSnapshot.included,
            ),
          ];

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
                for (final line in lines) ...[
                  Text(line.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${formatUnits(line.qty)} × ${formatMoney(currency, line.rate)} per day',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.charcoal),
                  ),
                  if (line.included.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Included with rental',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    const SizedBox(height: 4),
                    for (final included in line.included)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•  ', style: TextStyle(color: AppColors.charcoal)),
                            Expanded(
                              child: Text(included, style: const TextStyle(fontSize: 12.5, color: AppColors.charcoal)),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _expandAgreement() {
    final booking = _booking;
    if (booking == null) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: AppColors.white,
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 900,
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Rental Agreement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close & Minimize'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _AgreementContent(booking: booking, customerName: _customerName),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  int get _stepIndex => _step == _DocStep.documents ? 3 : (_step == _DocStep.agreement ? 4 : 5);

  String get _stepTitle {
    switch (_step) {
      case _DocStep.documents:
        return 'Verification Documents';
      case _DocStep.agreement:
        return 'Rental Agreement';
      case _DocStep.confirmation:
        return 'Booking Confirmation';
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = _booking;
    final currency = booking?.productSnapshot.currency ?? 'PHP';
    final rate = booking == null
        ? 0.0
        : (booking.dailyRate > 0
            ? booking.dailyRate
            : (booking.items.isNotEmpty ? booking.items.first.dailyRateSnapshot : booking.productSnapshot.pricePerDay));

    final isConfirmation = _step == _DocStep.confirmation;

    return PopScope(
      // On the confirmation screen the system Back goes to My Bookings —
      // going "back" into an already-submitted form would be misleading.
      canPop: !isConfirmation,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goToBookings();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Reserve')),
        body: ReservationFrame(
          productName: booking?.primaryProductName,
          dailyRateLabel: rate > 0 ? formatMoney(currency, rate) : null,
          savedAt: isConfirmation ? null : _savedAt,
          progressRestored: _restored,
          stepIndex: _stepIndex,
          stepTitle: _stepTitle,
          controller: _scroll,
          summaryBuilder: booking == null
              ? null
              : (collapsible) => SelectedRentalCard(
                    productName: booking.primaryProductName,
                    quantity: booking.totalQuantity,
                    totalLabel: formatMoney(currency, booking.totalAmount),
                    inventoryUnits: _inventoryUnits,
                    currentStep: _stepIndex + 1,
                    totalSteps: 6,
                    onReviewItemDetails: _showItemDetails,
                    collapsible: collapsible,
                  ),
          child: switch (_step) {
            _DocStep.documents => _buildDocumentsStep(),
            _DocStep.agreement => _buildAgreementStep(),
            _DocStep.confirmation => _buildConfirmationStep(),
          },
        ),
        bottomNavigationBar: ReservationActionBar(
          backLabel: isConfirmation ? 'All Bookings' : 'Back',
          onBack: _onBack,
          nextLabel: switch (_step) {
            _DocStep.documents => 'Continue',
            _DocStep.agreement => 'Sign & Submit Agreement',
            _DocStep.confirmation => 'Track Booking',
          },
          onNext: switch (_step) {
            _DocStep.documents => _canProceedDocuments ? _onContinue : null,
            _DocStep.agreement => _canSubmitAgreement ? _onContinue : null,
            _DocStep.confirmation => _onContinue,
          },
          busy: _submitting,
        ),
      ),
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
  // Step 4 — Verification Documents
  // ---------------------------------------------------------------------

  Widget _blurTracked(String key, Widget child) => Focus(
        onFocusChange: (hasFocus) {
          if (!hasFocus) setState(() => _touched.add(key));
        },
        child: child,
      );

  Widget _buildDocumentsStep() {
    final phoneText = _emergencyPhoneController.text.trim();
    final phoneInvalid = _touched.contains('ephone') && phoneText.isNotEmpty && !_isValidPhone(phoneText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepIntro(
          'Verification Document Submission',
          'Your reservation payment proof has been submitted and is pending admin verification. '
              'Now submit the documents needed to verify the renter. Accepted valid IDs: Passport, '
              "National ID, Driver's License, or School ID. At least one ID must show your current "
              'address and signature.',
        ),
        FieldGrid(
          wideColumns: 3,
          children: [
            LabeledField(
              label: 'First valid ID',
              child: DocumentUploadTile(
                semanticLabel: 'First valid ID',
                value: _idOne,
                onChanged: (v) => setState(() => _idOne = v),
              ),
            ),
            LabeledField(
              label: 'Second valid ID',
              note: 'At least one of your two IDs must show your current address and signature.',
              child: DocumentUploadTile(
                semanticLabel: 'Second valid ID',
                value: _idTwo,
                onChanged: (v) => setState(() => _idTwo = v),
              ),
            ),
            LabeledField(
              label: 'Selfie holding a valid ID',
              child: DocumentUploadTile(
                semanticLabel: 'Selfie holding a valid ID',
                value: _selfie,
                onChanged: (v) => setState(() => _selfie = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FieldGrid(
          wideColumns: 2,
          children: [
            LabeledField(label: 'Active Facebook profile link', child: _linkField(_facebookController, 'fb')),
            LabeledField(label: 'Active Instagram profile link', child: _linkField(_instagramController, 'ig')),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Emergency Contact', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        FieldGrid(
          wideColumns: 2,
          children: [
            LabeledField(
              label: 'Full name',
              child: TextField(
                controller: _emergencyFullNameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _onFieldChanged(),
              ),
            ),
            LabeledField(
              label: 'Relationship to you',
              child: TextField(
                controller: _emergencyRelationshipController,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                onChanged: (_) => _onFieldChanged(),
              ),
            ),
            LabeledField(
              label: 'Active phone number',
              note: 'Use exactly 11 digits.',
              noteColor: phoneInvalid ? AppColors.statusRed : AppColors.charcoal,
              child: _blurTracked(
                'ephone',
                TextField(
                  controller: _emergencyPhoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                  decoration: const InputDecoration(hintText: '09XXXXXXXXX'),
                  onChanged: (_) => _onFieldChanged(),
                ),
              ),
            ),
            LabeledField(label: 'Facebook profile link', child: _linkField(_emergencyFacebookController, 'efb')),
          ],
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: "Emergency contact's government-issued ID",
          child: DocumentUploadTile(
            semanticLabel: "Emergency contact's government-issued ID",
            value: _emergencyId,
            onChanged: (v) => setState(() => _emergencyId = v),
          ),
        ),
        const SizedBox(height: 20),
        _buildPrivacyNotice(),
      ],
    );
  }

  Widget _linkField(TextEditingController controller, String touchedKey) {
    final showError =
        _touched.contains(touchedKey) && controller.text.trim().isNotEmpty && _normalizeLink(controller.text) == null;
    return _blurTracked(
      touchedKey,
      TextField(
        controller: controller,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          errorText: showError ? 'Enter a valid profile link, e.g. https://facebook.com/yourname' : null,
          errorMaxLines: 2,
        ),
        onChanged: (_) => _onFieldChanged(),
      ),
    );
  }

  Widget _buildPrivacyNotice() {
    return NoticeBox(
      fillAlpha: 0.18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Privacy notice', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.charcoal),
              children: [
                const TextSpan(
                  text: 'These details and documents are collected for identity verification, fraud '
                      'prevention, booking administration, rental agreements, and rental-related '
                      'incidents. Private files are limited to you and active administrators. '
                      'Read the complete ',
                ),
                _privacyLinkSpan(),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextSpan _privacyLinkSpan() => TextSpan(
        text: 'Privacy Notice',
        recognizer: _privacyTap,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w800,
          decoration: TextDecoration.underline,
        ),
      );

  // ---------------------------------------------------------------------
  // Step 5 — Rental Agreement
  // ---------------------------------------------------------------------

  Widget _buildAgreementStep() {
    final booking = _booking;

    const heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('Rental Agreement & Terms', style: TextStyle(fontSize: 19, height: 1.25, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text(
          'Review the agreement, confirm both statements, then sign.',
          style: TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.charcoal),
        ),
      ],
    );
    final expandButton = OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.background,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        foregroundColor: AppColors.charcoal,
      ),
      onPressed: booking == null ? null : _expandAgreement,
      child: const Text('Expand Agreement'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 480) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: heading), const SizedBox(width: 12), expandButton],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: 10), expandButton],
            );
          },
        ),
        const SizedBox(height: 14),
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: AppColors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: booking == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'We could not load the agreement details. Go back and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.charcoal),
                    ),
                  ),
                )
              : Scrollbar(
                  controller: _agreementScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _agreementScroll,
                    padding: const EdgeInsets.all(14),
                    child: _AgreementContent(booking: booking, customerName: _customerName),
                  ),
                ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final confirmations = _buildConfirmations();
            final signature = _buildSignatureSection();
            if (constraints.maxWidth >= 720) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: confirmations),
                  const SizedBox(width: 24),
                  Expanded(child: signature),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [confirmations, const SizedBox(height: 20), signature],
            );
          },
        ),
        if (_submitting && _uploadStatus != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$_uploadStatus This can take a minute — please keep this screen open.',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.charcoal),
                ),
              ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: AppColors.statusRed)),
        ],
      ],
    );
  }

  Widget _buildConfirmations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Your Confirmations', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.background,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _confirmCard(
                value: _confirmInfoPrivacy,
                onChanged: (v) => setState(() => _confirmInfoPrivacy = v),
                title: 'Information & privacy',
                description: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.charcoal),
                    children: [
                      const TextSpan(
                        text: 'I confirm that my information and documents are accurate, my emergency contact '
                            'authorized their details, and I have read the ',
                      ),
                      _privacyLinkSpan(),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _confirmCard(
                value: _confirmTermsSignature,
                onChanged: (v) => setState(() => _confirmTermsSignature = v),
                title: 'Rental terms & signature',
                description: const Text(
                  'I agree to the Rental Terms, understand the return, care, damage, loss, and late-return '
                  'rules, and authorize my electronic signature.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.charcoal),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _confirmCard({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String title,
    required Widget description,
  }) {
    // A Material (not a coloured Container) so the ListTile's ink/ripple is visible
    // and Flutter stops logging "ListTile background color or ink splashes may be invisible".
    return Material(
      color: AppColors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: CheckboxListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        controlAffinity: ListTileControlAffinity.leading,
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 2), child: description),
      ),
    );
  }

  Widget _buildSignatureSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Electronic Signature', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _pill('Draw Signature', selected: _signatureMethod == 'drawn', onTap: () => setState(() => _signatureMethod = 'drawn')),
            _pill('Upload Signature Image',
                selected: _signatureMethod == 'uploaded', onTap: () => setState(() => _signatureMethod = 'uploaded')),
          ],
        ),
        const SizedBox(height: 12),
        if (_signatureMethod == 'drawn')
          SignaturePad(key: _signaturePadKey, onChanged: () => setState(() {}))
        else
          DocumentUploadTile(
            semanticLabel: 'Signature image',
            allowedExtensions: kImageExtensions, // backend rejects PDF signatures
            value: _uploadedSignature,
            onChanged: (v) => setState(() => _uploadedSignature = v),
          ),
        if (!_hasSignature) ...[
          const SizedBox(height: 6),
          const Text(
            'Your signature is required to continue.',
            style: TextStyle(fontSize: 11.5, color: AppColors.charcoal),
          ),
        ],
        const SizedBox(height: 14),
        LabeledField(
          label: 'Type your full name to sign',
          note: 'Signed on ${DateFormat('M/d/y, h:mm:ss a').format(DateTime.now())} — recorded at submission.',
          child: TextField(
            controller: _typedFullNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Your full legal name'),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  Widget _pill(String label, {required bool selected, required VoidCallback onTap}) {
    return Material(
      color: selected ? AppColors.primary : AppColors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.primary : AppColors.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Step 6 — Booking Confirmation
  // ---------------------------------------------------------------------

  Widget _buildConfirmationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Booking Confirmation', style: TextStyle(fontSize: 19, height: 1.25, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.statusGreenBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Your reservation is secured and your booking information has been submitted successfully.',
            style: TextStyle(fontSize: 15, height: 1.35, color: AppColors.statusGreen),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Booking $_bookingRef is now with the team for document verification. Once approved, its status '
          'will change to Confirmed. Your GCash payment receipt, proof of payment, and booking invoice are '
          'available in your account.',
          style: const TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.charcoal),
        ),
        const SizedBox(height: 14),
        NoticeBox(
          fillAlpha: 0.18,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Track this booking anytime from My Bookings.',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary),
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.charcoal),
                  children: [
                    const TextSpan(
                      text: 'Follow payment, document review, agreement, confirmation, and fulfillment from ',
                    ),
                    const TextSpan(text: 'My Bookings', style: TextStyle(fontWeight: FontWeight.w800)),
                    const TextSpan(text: '. Keep reference '),
                    TextSpan(text: _bookingRef, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const TextSpan(text: ' handy if you need to contact us.'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Agreement content (shown in the scroll box and in the expanded dialog)
// ---------------------------------------------------------------------------

class _AgreementContent extends StatelessWidget {
  final Booking booking;
  final String customerName;
  const _AgreementContent({required this.booking, required this.customerName});

  static const _terms = <String>[
    'Every rented item remains the property of Rental by Maddy & Cassy at all times.',
    'The customer agrees to return every item on or before the agreed return date, at the agreed pickup location or delivery arrangement.',
    "The customer is responsible for each item's care during the rental period and agrees to use it only for its intended purpose.",
    'Late returns may result in additional charges to be discussed and arranged directly with the business.',
    'Any damage, loss, or missing accessories will be assessed by the business, and the customer agrees to cooperate in resolving any related costs directly with the business.',
    'The reservation payment and any deposit shown in the checkout summary are non-refundable once payment is verified and the units are reserved.',
    'The reservation is secured after our team verifies the initial GCash payment. The booking becomes fully confirmed after the required verification documents and this signed agreement are approved by the business.',
    'This agreement, once electronically signed, is considered binding for this specific booking and every item listed above.',
  ];

  static const _privacy =
      'The personal information, identification documents, and photos you submit are collected solely to verify '
      'your identity and process this rental booking. Your information is stored securely and is only accessible '
      'to you and authorized personnel of Rental by Maddy & Cassy. It will not be shared with third parties except '
      'as required to fulfill this rental agreement.';

  @override
  Widget build(BuildContext context) {
    final currency = booking.productSnapshot.currency;
    final fmt = DateFormat('MMM d, y, h:mm a');
    final pickup = fmt.format(booking.pickupAt.toLocal());
    final returned = fmt.format(booking.returnAt.toLocal());
    final days = booking.dayCount;
    final isDelivery = booking.fulfillmentMethod == FulfillmentMethod.delivery;
    final location = isDelivery
        ? ((booking.location ?? '').trim().isEmpty ? '—' : booking.location!.trim())
        : 'Pickup — Right Focus Off Campus, Manuel Hizon, Sta. Cruz, Manila';

    final discounts = booking.specialDiscountAmount + booking.birthdayDiscountAmount + booking.loyaltyDiscountAmount;
    final convenience = booking.pickupConvenienceFee ?? 0;

    final items = booking.items.isNotEmpty
        ? booking.items
        : [
            BookingItem(
              bookingItemId: '',
              productId: '',
              productNameSnapshot: booking.productSnapshot.name,
              brand: booking.productSnapshot.brand,
              quantity: booking.quantity,
              dailyRateSnapshot: booking.productSnapshot.pricePerDay,
              lineRentalSubtotal: booking.rentalSubtotal,
            ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Rental Agreement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          'Booking Reference: ${booking.bookingReference.isEmpty ? booking.id : booking.bookingReference}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
        ),
        const SizedBox(height: 14),
        FieldGrid(
          wideColumns: 3,
          narrowColumns: 2,
          breakpoint: 440,
          gap: 12,
          children: [
            _kv('CUSTOMER', customerName),
            _kv('PICKUP & RETURN', '$pickup – $returned ($days ${days == 1 ? 'day' : 'days'})'),
            _kv('FULFILLMENT', isDelivery ? 'Delivery' : 'Pickup'),
          ],
        ),
        const SizedBox(height: 12),
        _kv('CUSTOMER LOCATION', location),
        const SizedBox(height: 16),
        const Text('Rented Items', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final item in items) ...[
          _itemCard(item, currency, days),
          const SizedBox(height: 8),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: [
              _moneyRow('Subtotal', formatMoney(currency, booking.rentalSubtotal)),
              if (booking.deliveryFee > 0) _moneyRow('Delivery fee', formatMoney(currency, booking.deliveryFee)),
              if (convenience > 0) _moneyRow('Convenience fee', formatMoney(currency, convenience)),
              if (discounts > 0) _moneyRow('Discounts', '-${formatMoney(currency, discounts)}'),
              _moneyRow('Refundable deposit', formatMoney(currency, booking.refundableDeposit)),
              const Divider(height: 16),
              _moneyRow('Final amount', formatMoney(currency, booking.totalAmount), bold: true),
            ],
          ),
        ),
        const Divider(height: 28),
        const Text('Rental Terms & Conditions', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (var i = 0; i < _terms.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text('${i + 1}.', style: const TextStyle(fontSize: 12.5, height: 1.45)),
                ),
                Expanded(child: Text(_terms[i], style: const TextStyle(fontSize: 12.5, height: 1.45))),
              ],
            ),
          ),
        const SizedBox(height: 14),
        const Text('Privacy Notice', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(_privacy, style: TextStyle(fontSize: 12.5, height: 1.5)),
      ],
    );
  }

  Widget _kv(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, letterSpacing: 0.6, color: AppColors.charcoal),
          ),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _itemCard(BookingItem item, String currency, int days) {
    final name = item.brand.trim().isEmpty ? item.productNameSnapshot : '${item.brand} — ${item.productNameSnapshot}';
    final lineTotal =
        item.lineRentalSubtotal > 0 ? item.lineRentalSubtotal : item.dailyRateSnapshot * item.quantity * days;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
              const SizedBox(width: 8),
              Text(formatMoney(currency, lineTotal), style: const TextStyle(fontSize: 12.5, color: AppColors.charcoal)),
            ],
          ),
          const SizedBox(height: 8),
          FieldGrid(
            wideColumns: 4,
            narrowColumns: 2,
            breakpoint: 440,
            gap: 12,
            children: [
              _kv('QUANTITY', formatUnits(item.quantity)),
              _kv('RATE', '${formatMoney(currency, item.dailyRateSnapshot)} / unit / day'),
              _kv('RENTAL DAYS', '$days'),
              _kv('LINE TOTAL', formatMoney(currency, lineTotal)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: bold ? 13.5 : 12, fontWeight: bold ? FontWeight.w800 : FontWeight.w500),
            ),
            Text(
              value,
              style: TextStyle(fontSize: bold ? 13.5 : 12, fontWeight: bold ? FontWeight.w800 : FontWeight.w600),
            ),
          ],
        ),
      );
}