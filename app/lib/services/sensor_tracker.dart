import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/emergency_config.dart';
import 'gps_processing_pipeline.dart';

class SensorTracker {
  SensorTracker._();

  static final instance = SensorTracker._();
  static const _microphoneChannel = EventChannel('roadrescue/microphone_rms');

  final _accelerationController = StreamController<double>.broadcast();
  final _speedController = StreamController<double>.broadcast();
  final _gyroscopeController = StreamController<double>.broadcast();
  final _barometerController = StreamController<double>.broadcast();
  final _gpsPipeline = GpsProcessingPipeline();
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<BarometerEvent>? _barometerSubscription;
  Position? _lastPosition;

  Stream<double> get accelerationG => _accelerationController.stream;
  Stream<double> get speedMph => _speedController.stream;
  Stream<double> get angularVelocityRadPerSecond => _gyroscopeController.stream;
  Stream<double> get pressureHpa => _barometerController.stream;
  Stream<double> get microphoneRms => _microphoneChannel
      .receiveBroadcastStream({'sampleRate': crashMicrophoneSampleRate}).map(
          (value) => (value as num).toDouble());
  Position? get lastPosition => _lastPosition;
  bool get isTracking =>
      _accelerometerSubscription != null && _positionSubscription != null;

  Future<void> start() async {
    if (isTracking) return;

    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'RoadRescue crash protection',
        notificationText: 'Monitoring movement while driving.',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    try {
      _accelerometerSubscription = accelerometerEventStream(
        samplingPeriod: crashSensorSamplingPeriod,
      ).listen(
        (event) {
          final magnitude = math.sqrt(
            event.x * event.x + event.y * event.y + event.z * event.z,
          );
          _accelerationController
              .add(magnitude / gravityMetersPerSecondSquared);
        },
        onError: _accelerationController.addError,
      );
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (position) {
          final speedMetersPerSecond =
              position.speed.isFinite && position.speed > 0
                  ? position.speed
                  : 0.0;
          _speedController
              .add(speedMetersPerSecond * metersPerSecondToMilesPerHour);
          _rememberFilteredPosition(position);
        },
        onError: _speedController.addError,
      );
      try {
        _gyroscopeSubscription = gyroscopeEventStream(
          samplingPeriod: crashSensorSamplingPeriod,
        ).listen(
          (event) {
            final magnitude = math.sqrt(
              event.x * event.x + event.y * event.y + event.z * event.z,
            );
            _gyroscopeController.add(magnitude);
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Optional gyroscope signal unavailable: $error');
          },
        );
      } catch (error) {
        debugPrint('Optional gyroscope sensor could not start: $error');
      }
      try {
        _barometerSubscription = barometerEventStream(
          samplingPeriod: const Duration(milliseconds: 100),
        ).listen(
          (event) => _barometerController.add(event.pressure),
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('Optional barometer signal unavailable: $error');
          },
        );
      } catch (error) {
        debugPrint('Optional barometer sensor could not start: $error');
      }
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<Position> currentPosition() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        timeLimit: Duration(seconds: 10),
      ),
    );
    final filtered = _rememberFilteredPosition(position);
    if (filtered == null) {
      throw StateError(
        'The latest GPS fix was rejected because its accuracy or movement was implausible.',
      );
    }
    return filtered;
  }

  Future<void> stop() async {
    final acceleration = _accelerometerSubscription;
    final position = _positionSubscription;
    final gyroscope = _gyroscopeSubscription;
    final barometer = _barometerSubscription;
    _accelerometerSubscription = null;
    _positionSubscription = null;
    _gyroscopeSubscription = null;
    _barometerSubscription = null;
    _gpsPipeline.reset();
    await acceleration?.cancel();
    await position?.cancel();
    await gyroscope?.cancel();
    await barometer?.cancel();
  }

  Position? _rememberFilteredPosition(Position position) {
    final processed = _gpsPipeline.process(GpsFix.fromPosition(position));
    if (processed == null) return null;
    _lastPosition = Position.fromMap({
      ...position.toJson(),
      'latitude': processed.latitude,
      'longitude': processed.longitude,
    });
    return _lastPosition;
  }
}
