import 'package:flutter_test/flutter_test.dart';
import 'package:roadrescue/services/gps_processing_pipeline.dart';

void main() {
  final start = DateTime.utc(2026, 10, 18);

  group('GPS fix filter and smoothing', () {
    test('rejects poor-accuracy fixes without moving the accepted anchor', () {
      final filter = GpsFixFilter();
      expect(filter.accept(_fix(start, accuracy: 10)), isTrue);
      expect(
        filter.accept(
          _fix(start.add(const Duration(seconds: 1)), accuracy: 51),
        ),
        isFalse,
      );
      expect(
        filter.accept(
          _fix(
            start.add(const Duration(seconds: 2)),
            latitude: 0.0001,
            accuracy: 10,
          ),
        ),
        isTrue,
      );
    });

    test('rejects impossible jumps and retains the last valid fix', () {
      final filter = GpsFixFilter();
      expect(filter.accept(_fix(start)), isTrue);
      expect(
        filter.accept(
          _fix(
            start.add(const Duration(seconds: 1)),
            latitude: 1,
          ),
        ),
        isFalse,
      );
      expect(
        filter.accept(
          _fix(
            start.add(const Duration(seconds: 2)),
            latitude: 0.0001,
          ),
        ),
        isTrue,
      );
    });

    test('rejects invalid coordinates and non-monotonic timestamps', () {
      final filter = GpsFixFilter();
      expect(filter.accept(_fix(start)), isTrue);
      expect(filter.accept(_fix(start, latitude: 91)), isFalse);
      expect(
        filter.accept(_fix(start.subtract(const Duration(seconds: 1)))),
        isFalse,
      );
    });

    test('haversine returns approximate surface distance', () {
      expect(
        haversineMeters(0, 0, 0, 1),
        closeTo(111195, 10),
      );
      expect(haversineMeters(0, 0, 0, 0), 0);
    });

    test('Kalman smoothing weights measurements by their accuracy', () {
      final filter = GpsKalman(qMetersPerSecond: 1);
      final first = filter.update(
        latitude: 0,
        longitude: 0,
        accuracyMeters: 5,
        timestamp: start,
      );
      final noisy = filter.update(
        latitude: 0,
        longitude: 1,
        accuracyMeters: 50,
        timestamp: start.add(const Duration(seconds: 1)),
      );

      expect(first, (0.0, 0.0));
      expect(noisy.$2, greaterThan(0));
      expect(noisy.$2, lessThan(0.1));
    });

    test('processing retains raw GPS speed while smoothing coordinates', () {
      final pipeline = GpsProcessingPipeline();
      final first = pipeline.process(_fix(start, speed: 5));
      final second = pipeline.process(
        _fix(
          start.add(const Duration(seconds: 1)),
          longitude: 0.0001,
          speed: 12,
        ),
      );

      expect(first!.rawSpeedMetersPerSecond, 5);
      expect(second!.rawSpeedMetersPerSecond, 12);
      expect(second.longitude, lessThan(0.0001));
    });
  });

  group('motion state', () {
    test('enters driving after speed exceeds 10 mph for ten seconds', () {
      final detector = MotionStateDetector();
      expect(
        detector.update(speedMph: 11, timestamp: start),
        MotionState.stationary,
      );
      expect(
        detector.update(
          speedMph: 11,
          timestamp: start.add(const Duration(seconds: 9)),
        ),
        MotionState.stationary,
      );
      expect(
        detector.update(
          speedMph: 11,
          timestamp: start.add(const Duration(seconds: 10)),
        ),
        MotionState.driving,
      );
    });

    test('requires two minutes below 2 mph to stop a driving trip', () {
      final detector = MotionStateDetector();
      detector.update(speedMph: 11, timestamp: start);
      detector.update(
        speedMph: 11,
        timestamp: start.add(const Duration(seconds: 10)),
      );
      expect(
        detector.update(
          speedMph: 1,
          timestamp: start.add(const Duration(seconds: 20)),
        ),
        MotionState.driving,
      );
      expect(
        detector.update(
          speedMph: 1,
          timestamp: start.add(const Duration(minutes: 2, seconds: 19)),
        ),
        MotionState.driving,
      );
      expect(
        detector.update(
          speedMph: 1,
          timestamp: start.add(const Duration(minutes: 2, seconds: 20)),
        ),
        MotionState.stationary,
      );
    });

    test('classifies sustained walking pace and ignores stale samples', () {
      final detector = MotionStateDetector();
      expect(
        detector.update(speedMph: 3, timestamp: start),
        MotionState.stationary,
      );
      expect(
        detector.update(
          speedMph: 3,
          timestamp: start.add(const Duration(seconds: 30)),
        ),
        MotionState.walking,
      );
      expect(
        detector.update(
          speedMph: 11,
          timestamp: start.add(const Duration(seconds: 20)),
        ),
        MotionState.walking,
      );
    });

    test('selects progressively lower-power location settings', () {
      expect(
        locationSettingsForMotion(MotionState.driving).distanceFilter,
        0,
      );
      expect(
        locationSettingsForMotion(MotionState.walking).distanceFilter,
        25,
      );
      expect(
        locationSettingsForMotion(MotionState.stationary).distanceFilter,
        100,
      );
    });
  });

  group('location upload throttle', () {
    test('emergency upload is immediate regardless of movement or time', () {
      expect(
        shouldUploadLocation(
          movedMeters: 0,
          sinceLastUpload: Duration.zero,
          emergency: true,
        ),
        isTrue,
      );
    });

    test('ordinary uploads wait for movement or two-minute heartbeat', () {
      expect(
        shouldUploadLocation(
          movedMeters: 49.9,
          sinceLastUpload: const Duration(minutes: 1, seconds: 59),
          emergency: false,
        ),
        isFalse,
      );
      expect(
        shouldUploadLocation(
          movedMeters: 50,
          sinceLastUpload: Duration.zero,
          emergency: false,
        ),
        isTrue,
      );
      expect(
        shouldUploadLocation(
          movedMeters: 0,
          sinceLastUpload: const Duration(minutes: 2),
          emergency: false,
        ),
        isTrue,
      );
    });
  });
}

GpsFix _fix(
  DateTime timestamp, {
  double latitude = 0,
  double longitude = 0,
  double accuracy = 5,
  double speed = 0,
}) =>
    GpsFix(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracy,
      timestamp: timestamp,
      rawSpeedMetersPerSecond: speed,
    );
