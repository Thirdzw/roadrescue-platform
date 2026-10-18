class Vehicle {
  final String id;
  final String ownerId;
  final String make;
  final String model;
  final String plateNumber;

  const Vehicle({
    required this.id,
    required this.ownerId,
    required this.make,
    required this.model,
    required this.plateNumber,
  });

  factory Vehicle.fromMap(String id, Map<String, dynamic> map) {
    return Vehicle(
      id: id,
      ownerId: map['ownerId'] as String? ?? '',
      make: map['make'] as String? ?? '',
      model: map['model'] as String? ?? '',
      plateNumber: map['plateNumber'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'ownerId': ownerId,
        'make': make,
        'model': model,
        'plateNumber': plateNumber,
      };
}
