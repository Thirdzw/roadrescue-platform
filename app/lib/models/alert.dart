enum AlertType { crash, panicButton, predictiveFault }

class EmergencyAlert {
  final String id;
  final String motoristId;
  final String vehicleId;
  final AlertType type;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool dispatched; // confirmed sent to police/ambulance

  EmergencyAlert({
    required this.id,
    required this.motoristId,
    required this.vehicleId,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.dispatched = false,
  });

  factory EmergencyAlert.fromMap(String id, Map<String, dynamic> map) {
    return EmergencyAlert(
      id: id,
      motoristId: map['motoristId'] ?? '',
      vehicleId: map['vehicleId'] ?? '',
      type: AlertType.values.firstWhere(
        (t) => t.name == map['type'],
        orElse: () => AlertType.panicButton,
      ),
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
      dispatched: map['dispatched'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'motoristId': motoristId,
        'vehicleId': vehicleId,
        'type': type.name,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
        'dispatched': dispatched,
      };
}
