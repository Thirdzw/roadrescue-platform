class Vehicle {
  final String id;
  final String ownerId;
  final String make;
  final String model;
  final String plateNumber;
  final Map<String, dynamic> lastHealthReading; // engine, battery, tyre data

  Vehicle({
    required this.id,
    required this.ownerId,
    required this.make,
    required this.model,
    required this.plateNumber,
    this.lastHealthReading = const {},
  });

  factory Vehicle.fromMap(String id, Map<String, dynamic> map) {
    return Vehicle(
      id: id,
      ownerId: map['ownerId'] ?? '',
      make: map['make'] ?? '',
      model: map['model'] ?? '',
      plateNumber: map['plateNumber'] ?? '',
      lastHealthReading:
          Map<String, dynamic>.from(map['lastHealthReading'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() => {
        'ownerId': ownerId,
        'make': make,
        'model': model,
        'plateNumber': plateNumber,
        'lastHealthReading': lastHealthReading,
      };
}
