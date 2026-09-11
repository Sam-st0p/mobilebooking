// lib/models/reservation_draft.dart

import 'dart:io';

/// Port of `src/types/reservationDraft.ts`. `File` here is `dart:io File`
/// (a picked image on disk) — the mobile equivalent of the browser's `File`.
enum FulfillmentMethod { pickup, delivery }

enum PaymentOption { deposit50, full }

String paymentOptionToApiValue(PaymentOption option) =>
    option == PaymentOption.deposit50 ? 'deposit_50' : 'full';

enum SignatureMethod { drawn, uploaded }

class EmergencyContactDraft {
  String fullName;
  String relationship;
  String phone;
  String facebookLink;
  File? idFile;

  EmergencyContactDraft({
    this.fullName = '',
    this.relationship = '',
    this.phone = '',
    this.facebookLink = '',
    this.idFile,
  });
}

class RequirementsDraft {
  File? idOneFile;
  File? idTwoFile;
  File? selfieFile;
  String facebookLink;
  String instagramLink;
  EmergencyContactDraft emergencyContact;

  RequirementsDraft({
    this.idOneFile,
    this.idTwoFile,
    this.selfieFile,
    this.facebookLink = '',
    this.instagramLink = '',
    EmergencyContactDraft? emergencyContact,
  }) : emergencyContact = emergencyContact ?? EmergencyContactDraft();
}

class CustomerInfoDraft {
  String fullName;
  String email;
  String phone;
  String address;
  String facebookLink;
  String instagramLink;

  CustomerInfoDraft({
    this.fullName = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.facebookLink = '',
    this.instagramLink = '',
  });
}

class AgreementDraft {
  bool infoAccurate;
  bool agreedToTerms;
  bool understoodRentalRules;
  bool authorizedESignature;
  bool readPrivacyNotice;
  bool emergencyContactAuthorized;
  SignatureMethod signatureMethod;
  /// Signature encoded as a `data:image/png;base64,...` URL, same as the
  /// web app (SignatureCanvas.toDataURL / FileReader.readAsDataURL).
  String? signatureDataUrl;
  String typedFullName;

  AgreementDraft({
    this.infoAccurate = false,
    this.agreedToTerms = false,
    this.understoodRentalRules = false,
    this.authorizedESignature = false,
    this.readPrivacyNotice = false,
    this.emergencyContactAuthorized = false,
    this.signatureMethod = SignatureMethod.drawn,
    this.signatureDataUrl,
    this.typedFullName = '',
  });

  bool get allConfirmed =>
      infoAccurate &&
      agreedToTerms &&
      understoodRentalRules &&
      authorizedESignature &&
      readPrivacyNotice &&
      emergencyContactAuthorized;
}

class ReservationDraft {
  DateTime? startDate;
  DateTime? endDate;
  FulfillmentMethod? fulfillmentMethod;
  String customerLocation;
  String cityMunicipality;
  String province;
  PaymentOption paymentOption;
  CustomerInfoDraft customerInfo;
  RequirementsDraft requirements;
  AgreementDraft agreement;

  ReservationDraft({
    this.startDate,
    this.endDate,
    this.fulfillmentMethod,
    this.customerLocation = '',
    this.cityMunicipality = '',
    this.province = '',
    this.paymentOption = PaymentOption.deposit50,
    CustomerInfoDraft? customerInfo,
    RequirementsDraft? requirements,
    AgreementDraft? agreement,
  })  : customerInfo = customerInfo ?? CustomerInfoDraft(),
        requirements = requirements ?? RequirementsDraft(),
        agreement = agreement ?? AgreementDraft();
}

/// Pickup never carries a delivery address (see create_booking RPC), so it
/// always shows the fixed pickup site instead of blank fields.
String formatCustomerLocation(ReservationDraft draft) {
  if (draft.fulfillmentMethod == FulfillmentMethod.pickup) {
    return 'Pickup — Right Focus Off Campus, Manuel Hizon, Sta. Cruz, Manila';
  }
  return [draft.customerLocation, draft.cityMunicipality, draft.province]
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .join(', ');
}

int getDayCount(DateTime? startDate, DateTime? endDate) {
  if (startDate == null || endDate == null) return 0;
  final start = DateTime(startDate.year, startDate.month, startDate.day);
  final end = DateTime(endDate.year, endDate.month, endDate.day);
  return end.difference(start).inDays + 1;
}
