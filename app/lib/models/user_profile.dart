enum UserRole { motorist, mechanic, admin }

class UserProfile {
  final String uid;
  final String name;
  final String phone;
  final UserRole role;
  final double? rating; // mechanics only
  final bool verified; // mechanics only — vetted before joining

  UserProfile({
    required this.uid,
    required this.name,
    required this.phone,
    required this.role,
    this.rating,
    this.verified = false,
  });

  factory UserProfile.fromMap(String uid, Map<String, dynamic> map) {
    return UserProfile(
      uid: uid,
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      role: UserRole.values.firstWhere(
        (r) => r.name == map['role'],
        orElse: () => UserRole.motorist,
      ),
      rating: (map['rating'] as num?)?.toDouble(),
      verified: map['verified'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'phone': phone,
        'role': role.name,
        'rating': rating,
        'verified': verified,
      };
}
