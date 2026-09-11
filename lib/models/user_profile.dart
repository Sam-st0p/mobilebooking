// lib/models/user_profile.dart
/// Matches the JSON returned by GET/PUT /api/mobile/account/profile.
class UserProfile {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String displayName;
  final String? phoneNumber;
  final String? birthDate;
  final String? fullAddress;
  final String? facebookLink;
  final String? instagramLink;
  final String accountStatus;
  final String? photoPath;
  final String? photoUrl;
  final String createdAt;
  final String updatedAt;

  const UserProfile({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    required this.displayName,
    this.phoneNumber,
    this.birthDate,
    this.fullAddress,
    this.facebookLink,
    this.instagramLink,
    required this.accountStatus,
    this.photoPath,
    this.photoUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
      displayName: json['displayName'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String?,
      birthDate: json['birthDate'] as String?,
      fullAddress: json['fullAddress'] as String?,
      facebookLink: json['facebookLink'] as String?,
      instagramLink: json['instagramLink'] as String?,
      accountStatus: json['accountStatus'] as String? ?? 'active',
      photoPath: json['photoPath'] as String?,
      photoUrl: json['photoUrl'] as String?,
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}
