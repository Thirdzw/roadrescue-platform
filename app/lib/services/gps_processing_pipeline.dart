import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

const gpsMaximumAccuracyMeters = 50.0;
const gpsMaximumPlausibleSpeedMetersPerSecond = 70.0;
const gpsKalmanProcessNoiseMetersPerSecond = 3.0;
const gpsDrivingEntrySpeedMph = 10.0;
const gpsDrivingEntryDuration = Duration(seconds: 10);
const gpsStoppedSpeedMph = 2.0;
const gpsTripStopDuration = Duration(minutes: 2);
const gpsWalkingMinimumSpeedMph = 1.0;
const gpsWalkingMaximumSpeedMph = 5.0;
const gpsWalkingConfirmationDuration = Duration(seconds: 30);

double haversineMeters(
  double latitude1,
  double longitude1,
  double latitude2,
  double longitude2,
) {
  const earthRadiusMeters = 6371000.0;
  final latitudeDelta = (latitude2 - latitude1) * math.pi / 180;
  final longitudeDelta = (longitude2 - longitude1) * math.pi / 180;
  final haversine = math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(latitude1 * math.pi / 180) *
          math.cos(latitude2 * math.pi / 180) *
          math.pow(math.sin(longitudeDelta / 2), 2);
  final bounded = haversine.clamp(0.0, 1.0);
  return 2 * earthRadiusMeters * math.asin(math.sqrt(bounded));
}

class GpsFix {
  const GpsFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
    required this.rawSpeedMetersPerSecond,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;
  final double rawSpeedMetersPerSecond;

  factory GpsFix.fromPosition(Position position) => GpsFix(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        timestamp: position.timestamp,
        rawSpeedMetersPerSecond: position.speed,
      );
}

class ProcessedGpsFix {
  const ProcessedGpsFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
    required this.rawSpeedMetersPerSecond,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;

  /// Preserved from Position.speed for driving/crash decisions.
  final double rawSpeedMetersPerSecond;

  Position toPosition() => Position(
        latitude: latitude,
        longitude: longitude,
        timestamp: timestamp,
        accuracy: accuracyMeters,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: rawSpeedMetersPerSecond,
        speedAccuracy: 0,
      );
}

class GpsFixFilter {
  GpsFix? _lastAccepted;

  bool accept(GpsFix fix) {
    if (!fix.latitude.isFinite ||
        !fix.longitude.isFinite ||
        fix.latitude < -90 ||
        fix.latitude > 90 ||
        fix.longitude < -180 ||
        fix.longitude > 180 ||
        !fix.accuracyMeters.isFinite ||
        fix.accuracyMeters < 0 ||
        fix.accuracyMeters > gpsMaximumAccuracyMeters ||
        !fix.rawSpeedMetersPerSecond.isFinite ||
        fix.rawSpeedMetersPerSecond < 0) {
      return false;
    }

    final previous = _lastAccepted;
    if (previous != null) {
      final elapsed = fix.timestamp.difference(previous.timestamp);
      if (elapsed <= Duration.zero) return false;
      final distance = haversineMeters(
        previous.latitude,
        previous.longitude,
        fix.latitude,
        fix.longitude,
      );
      if (!distance.isFinite ||
          distance / elapsed.inMicroseconds * Duration.microsecondsPerSecond >
              gpsMaximumPlausibleSpeedMetersPerSecond) {
        return false;
      }
    }
    _lastAccepted = fix;
    return true;
  }

  void reset() => _lastAccepted = null;
}

class GpsKalman {
  GpsKalman({
    this.qMetersPerSecond = gpsKalmanProcessNoiseMetersPerSecond,
  }) : assert(qMetersPerSecond > 0);

  final double qMetersPerSecond;
  double? _latitude;
  double? _longitude;
  double _variance = -1;
  DateTime? _timestamp;

  (double, double) update({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime timestamp,
  }) {
    final measurementVariance =
        math.pow(math.max(1.0, accuracyMeters), 2).toDouble();
    if (_variance < 0) {
      _latitude = latitude;
      _longitude = longitude;
      _variance = measurementVariance;
      _timestamp = timestamp;
      return (latitude, longitude);
    }

    final previousTimestamp = _timestamp!;
    final elapsedMilliseconds =
        timestamp.difference(previousTimestamp).inMilliseconds;
    if (elapsedMilliseconds <= 0) {
      return (_latitude!, _longitude!);
    }

    _variance += elapsedMilliseconds *
        qMetersPerSecond *
        qMetersPerSecond /
        1000;
    _timestamp = timestamp;
    final gain = _variance / (_variance + measurementVariance);
    _latitude = _latitude! + gain * (latitude - _latitude!);
    _longitude = _longitude! + gain * (longitude - _longitude!);
    _variance = (1 - gain) * _variance;
    return (_latitude!, _longitude!);
  }

  void reset() {
    _latitude = null;
    _longitude = null;
    _timestamp = null;
    _variance = -1;
  }
}

class GpsProcessingPipeline {
  GpsProcessingPipeline({double processNoiseMetersPerSecond = 3})
      : _processNoiseMetersPerSecond = processNoiseMetersPerSecond,
        _kalman = GpsKalman(qMetersPerSecond: processNoiseMetersPerSecond);

  final GpsFixFilter _filter = GpsFixFilter();
  GpsKalman _kalman;
  double _processNoiseMetersPerSecond;

  ProcessedGpsFix? process(GpsFix fix) {
    if (!_filter.accept(fix)) return null;
    final (latitude, longitude) = _kalman.update(
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracyMeters: fix.accuracyMeters,
      timestamp: fix.timestamp,
    );
    return ProcessedGpsFix(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: fix.accuracyMeters,
      timestamp: fix.timestamp,
      rawSpeedMetersPerSecond: fix.rawSpeedMetersPerSecond,
    );
  }

  void setProcessNoise(double metersPerSecond) {
    if (metersPerSecond == _processNoiseMetersPerSecond) return;
    if (!metersPerSecond.isFinite || metersPerSecond <= 0) {
      throw ArgumentError.value(metersPerSecond, 'metersPerSecond');
    }
    _processNoiseMetersPerSecond = metersPerSecond;
    reset();
    _kalman = GpsKalman(qMetersPerSecond: metersPerSecond);
  }

  void reset() {
    _filter.reset();
    _kalman.reset();
  }
}

enum MotionState { stationary, walking, driving }

class MotionStateDetector {
  MotionState state = MotionState.stationary;
  DateTime? _lastTimestamp;
  DateTime? _drivingSince;
  DateTime? _walkingSince;
  DateTime? _stoppedSince;

  MotionState update({
    required double speedMph,
    required DateTime timestamp,
  }) {
    if (!speedMph.isFinite ||
        speedMph < 0 ||
        (_lastTimestamp != null && !timestamp.isAfter(_lastTimestamp!))) {
      return state;
    }
    _lastTimestamp = timestamp;

    if (speedMph > gpsDrivingEntrySpeedMph) {
      _drivingSince ??= timestamp;
      _walkingSince = null;
      _stoppedSince = null;
      if (timestamp.difference(_drivingSince!) >= gpsDrivingEntryDuration) {
        state = MotionState.driving;
      }
      return state;
    }
    _drivingSince = null;

    if (speedMph < gpsStoppedSpeedMph) {
      _stoppedSince ??= timestamp;
      _walkingSince = null;
      if (state == MotionState.driving &&
          timestamp.difference(_stoppedSince!) >= gpsTripStopDuration) {
        state = MotionState.stationary;
      } else if (state == MotionState.walking) {
        state = MotionState.stationary;
      }
      return state;
    }
    _stoppedSince = null;

    if (speedMph >= gpsWalkingMinimumSpeedMph &&
        speedMph <= gpsWalkingMaximumSpeedMph &&
        state != MotionState.driving) {
      _walkingSince ??= timestamp;
      if (timestamp.difference(_walkingSince!) >=
          gpsWalkingConfirmationDuration) {
        state = MotionState.walking;
      }
    } else {
      _walkingSince = null;
    }
    return state;
  }

  void reset() {
    state = MotionState.stationary;
    _lastTimestamp = null;
    _drivingSince = null;
    _walkingSince = null;
    _stoppedSince = null;
  }
}

LocationSettings locationSettingsForMotion(MotionState state) {
  return switch (state) {
    MotionState.driving => const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    MotionState.walking => const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      ),
    MotionState.stationary => const LocationSettings(
        accuracy: LocationAccuracy.low,
        distanceFilter: 100,
      ),
  };
}

bool shouldUploadLocation({
  required double movedMeters,
  required Duration sinceLastUpload,
  required bool emergency,
}) {
  if (emergency) return true;
  if (!movedMeters.isFinite || movedMeters < 0) return false;
  return movedMeters >= 50 ||
      sinceLastUpload >= const Duration(minutes: 2);
}
