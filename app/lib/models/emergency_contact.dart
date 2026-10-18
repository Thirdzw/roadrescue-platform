import 'contact.dart';

class EmergencyContact extends Contact {
  const EmergencyContact({
    required super.id,
    required super.name,
    required super.phone,
    super.type = ContactType.emergencyContact,
    super.userId,
    super.relationship,
  });

  factory EmergencyContact.fromMap(String id, Map<String, dynamic> map) {
    final contact = Contact.fromMap(id, map);
    return EmergencyContact(
      id: contact.id,
      name: contact.name,
      phone: contact.phone,
      type: contact.type,
      userId: contact.userId,
      relationship: contact.relationship,
    );
  }
}
