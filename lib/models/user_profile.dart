// lib/models/user_profile.dart

/// Port of the `UserProfile` interface in `src/types/database.ts`.
class UserProfile {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String displayName;
  final String? phoneNumber;
  final String? fullAddress;
  final String? facebookLink;
  final String? instagramLink;
  final String accountStatus;
  final String? photoPath;
  final String createdAt;
  final String updatedAt;

  const UserProfile({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    required this.displayName,
    this.phoneNumber,
    this.fullAddress,
    this.facebookLink,
    this.instagramLink,
    required this.accountStatus,
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.fromRow(Map<String, dynamic> row) {
    return UserProfile(
      id: row['id'] as String,
      email: (row['contact_email'] as String?) ?? '',
      firstName: row['first_name'] as String?,
      lastName: row['last_name'] as String?,
      displayName: row['display_name'] as String? ?? '',
      phoneNumber: row['phone_number'] as String?,
      fullAddress: row['full_address'] as String?,
      facebookLink: row['facebook_url'] as String?,
      instagramLink: row['instagram_url'] as String?,
      accountStatus: row['account_status'] as String? ?? 'active',
      photoPath: row['photo_path'] as String?,
      createdAt: row['created_at'] as String,
      updatedAt: row['updated_at'] as String,
    );
  }
}
