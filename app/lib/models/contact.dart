enum ContactType { circleMember, emergencyContact }

class Contact {
  final String id;
  final String name;
  final String phone;
  final ContactType type;
  final String? userId;
  final String relationship;

  const Contact({
    required this.id,
    required this.name,
    required this.phone,
    required this.type,
    this.userId,
    this.relationship = '',
  });

  factory Contact.fromMap(String id, Map<String, dynamic> map) {
    final typeName = map['type'] as String?;
    return Contact(
      id: id,
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      type: ContactType.values.firstWhere(
        (type) => type.name == typeName,
        orElse: () => ContactType.emergencyContact,
      ),
      userId: (map['userId'] as String?)?.trim().isEmpty == true
          ? null
          : map['userId'] as String?,
      relationship: map['relationship'] as String? ?? '',
    );
  }

  Map<String, Object?> toMap() => {
        'name': name.trim(),
        'phone': phone.trim(),
        'type': type.name,
        'relationship': relationship.trim(),
        if (userId != null && userId!.trim().isNotEmpty)
          'userId': userId!.trim(),
      };
}
