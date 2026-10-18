import 'package:flutter_test/flutter_test.dart';
import 'package:roadrescue/models/job.dart';

void main() {
  test('rescue request serializes consent and service category', () {
    final job = Job(
      id: 'job-1',
      motoristId: 'client-1',
      latitude: -17.8252,
      longitude: 31.0335,
      status: JobStatus.requested,
      createdAt: DateTime.utc(2026, 10, 18),
      serviceType: 'Towing',
      locationSharingEnabled: true,
    );

    final restored = Job.fromMap(job.id, job.toMap());

    expect(restored.status, JobStatus.requested);
    expect(restored.serviceType, 'Towing');
    expect(restored.locationSharingEnabled, isTrue);
    expect(restored.latitude, -17.8252);
    expect(restored.longitude, 31.0335);
  });

  test('legacy jobs default to no live location sharing', () {
    final job = Job.fromMap('legacy', {
      'motoristId': 'client-1',
      'mechanicId': null,
      'latitude': -17.8252,
      'longitude': 31.0335,
      'status': 'requested',
      'createdAt': '2026-10-18T00:00:00.000Z',
    });

    expect(job.locationSharingEnabled, isFalse);
    expect(job.serviceType, 'Roadside assistance');
  });
}
