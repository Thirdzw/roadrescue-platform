enum JobStatus { requested, matched, enRoute, completed, cancelled }

class Job {
  final String id;
  final String motoristId;
  final String? mechanicId;
  final double latitude;
  final double longitude;
  final JobStatus status;
  final DateTime createdAt;
  final String? notes;

  Job({
    required this.id,
    required this.motoristId,
    this.mechanicId,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.createdAt,
    this.notes,
  });

  factory Job.fromMap(String id, Map<String, dynamic> map) {
    return Job(
      id: id,
      motoristId: map['motoristId'] ?? '',
      mechanicId: map['mechanicId'],
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      status: JobStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => JobStatus.requested,
      ),
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      notes: map['notes'],
    );
  }

  Map<String, dynamic> toMap() => {
        'motoristId': motoristId,
        'mechanicId': mechanicId,
        'latitude': latitude,
        'longitude': longitude,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'notes': notes,
      };
}
