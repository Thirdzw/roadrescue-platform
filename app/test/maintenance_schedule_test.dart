import 'package:flutter_test/flutter_test.dart';
import 'package:roadrescue/models/maintenance_schedule.dart';

void main() {
  group('MaintenanceSchedule', () {
    final start = DateTime.utc(2026, 1, 1);

    test('estimates current mileage from recorded mileage plus GPS distance', () {
      final schedule = MaintenanceSchedule(
        lastServiceOdometerKm: 120000,
        lastServiceDate: DateTime.utc(2026, 1, 1),
        distanceSinceServiceKm: 125.5,
        serviceIntervalKm: 5000,
        serviceIntervalDays: 180,
      );

      expect(schedule.estimatedOdometerKm, 120125.5);
      expect(schedule.nextServiceOdometerKm, 125000);
      expect(schedule.remainingDistanceKm, 4874.5);
      expect(schedule.isDueAt(start.add(const Duration(days: 90))), isFalse);
    });

    test('reminds when either mileage or time interval is due', () {
      final mileageDue = MaintenanceSchedule(
        lastServiceOdometerKm: 1000,
        lastServiceDate: DateTime.utc(2026, 1, 1),
        distanceSinceServiceKm: 5000,
        serviceIntervalKm: 5000,
        serviceIntervalDays: 180,
      );
      final timeDue = MaintenanceSchedule(
        lastServiceOdometerKm: 1000,
        lastServiceDate: DateTime.utc(2026, 1, 1),
        distanceSinceServiceKm: 100,
        serviceIntervalKm: 5000,
        serviceIntervalDays: 180,
      );

      expect(mileageDue.isDueAt(start.add(const Duration(days: 20))), isTrue);
      expect(timeDue.isDueAt(start.add(const Duration(days: 181))), isTrue);
      expect(timeDue.remainingDays(start.add(const Duration(days: 10))), 170);
    });
  });
}
