import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/emergency_config.dart';
import 'gps_processing_pipeline.dart';
import 'demo_session.dart';

class LocationService extends ChangeNotifier {
  LocationService._();

  static final instance = LocationService._();

  final _positionController = StreamController<Position>.broadcast();
  final _pipeline = GpsProcessingPipeline();
  final _motionDetector = MotionStateDetector();
  StreamSubscription<Position>? _subscription;
  Position? _lastPosition;
  MotionState _motionState = MotionState.stationary;
  Future<void> _settingsUpdate = Future<void>.value();
  int _subscriptionGeneration = 0;
  bool _demoTracking = false;
  bool _lastPositionIsDemo = false;

  Stream<Position> get positions => _positionController.stream;
  Position? get lastPosition => _lastPosition;
  MotionState get motionState => _motionState;
  bool get isTracking => _demoTracking || _subscription != null;

  Future<bool> startTracking() async {
    if (isTracking) return true;
    if (DemoSession.instance.isActive) {
      _demoTracking = true;
      _motionState = MotionState.stationary;
      notifyListeners();
      return true;
    }
    await _requireForegroundLocationPermission();
    _pipeline.reset();
    _motionDetector.reset();
    _motionState = MotionState.stationary;
    _listenForPositionUpdates();
    return true;
  }

  Future<void> stopTracking() async {
    _demoTracking = false;
    final subscription = _subscription;
    _subscription = null;
    _subscriptionGeneration++;
    await subscription?.cancel();
    _pipeline.reset();
    _motionDetector.reset();
    _motionState = MotionState.stationary;
    notifyListeners();
  }

  Future<Position> getCurrentLocation({bool requestPermission = true}) async {
    if (DemoSession.instance.isActive) {
      final position = Position.fromMap({
        'latitude': DemoSession.locationLatitude,
        'longitude': DemoSession.locationLongitude,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'accuracy': 20.0,
        'altitude': 0.0,
        'heading': 0.0,
        'speed': 0.0,
        'speed_accuracy': 0.0,
        'altitude_accuracy': 0.0,
        'heading_accuracy': 0.0,
        'is_mocked': true,
      });
      _lastPosition = position;
      _lastPositionIsDemo = true;
      _positionController.add(position);
      notifyListeners();
      return position;
    }
    try {
      await _requireForegroundLocationPermission(
        requestPermission: requestPermission,
      );
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      _rememberPosition(position);
      return position;
    } catch (_) {
      final fallback = await _getLastKnownPosition();
      if (fallback != null) return fallback;
      rethrow;
    }
  }

  Future<void> _requireForegroundLocationPermission({
    bool requestPermission = false,
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationAccessException(
        'Location services are turned off.',
      );
    }

    final permission = await Geolocator.checkPermission();
    var grantedPermission = permission;
    if (permission == LocationPermission.denied && requestPermission) {
      grantedPermission = await Geolocator.requestPermission();
    }
    if (grantedPermission == LocationPermission.deniedForever) {
      throw const LocationAccessException(
        'Location permission is blocked. Enable it in app settings.',
        settingsRequired: true,
      );
    }
    if (grantedPermission == LocationPermission.denied) {
      throw const LocationAccessException(
          'Location permission was not granted.');
    }
  }

  Future<Position?> _getLastKnownPosition() async {
    final cached = _lastPosition;
    if (cached != null) return cached;
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) _rememberPosition(lastKnown);
      return lastKnown;
    } catch (_) {
      return null;
    }
  }

  void _rememberPosition(Position position) {
    _lastPositionIsDemo = false;
    final processed = _pipeline.process(GpsFix.fromPosition(position));
    if (processed != null) {
      _lastPosition = _withSmoothedCoordinates(position, processed);
      _positionController.add(_lastPosition!);
    }
    notifyListeners();
  }

  void clearDemoPosition() {
    if (_lastPositionIsDemo) _lastPosition = null;
    _lastPositionIsDemo = false;
    _demoTracking = false;
    notifyListeners();
  }

  void _listenForPositionUpdates() {
    final generation = ++_subscriptionGeneration;
    _subscription = Geolocator.getPositionStream(
      locationSettings: _settingsForMotion(_motionState),
    ).listen(
      (position) {
        if (generation != _subscriptionGeneration) return;
        _onRawPosition(position);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (generation == _subscriptionGeneration) {
          _positionController.addError(error, stackTrace);
        }
      },
    );
  }

  void _onRawPosition(Position rawPosition) {
    final rawSpeedMph = (rawPosition.speed < 0 ? 0.0 : rawPosition.speed) *
        metersPerSecondToMilesPerHour;
    final nextMotionState = _motionDetector.update(
      speedMph: rawSpeedMph,
      timestamp: rawPosition.timestamp,
    );
    if (nextMotionState != _motionState) {
      _motionState = nextMotionState;
      _pipeline.setProcessNoise(switch (nextMotionState) {
        MotionState.driving => 10,
        MotionState.walking => 1,
        MotionState.stationary => 3,
      });
      _settingsUpdate = _settingsUpdate.then((_) => _restartForMotionState());
      notifyListeners();
    }

    final processed = _pipeline.process(GpsFix.fromPosition(rawPosition));
    if (processed == null) return;
    _lastPosition = _withSmoothedCoordinates(rawPosition, processed);
    _positionController.add(_lastPosition!);
    notifyListeners();
  }

  Future<void> _restartForMotionState() async {
    if (!isTracking) return;
    final oldSubscription = _subscription;
    _subscription = null;
    _subscriptionGeneration++;
    await oldSubscription?.cancel();
    if (isTracking) return;
    _listenForPositionUpdates();
  }

  LocationSettings _settingsForMotion(MotionState state) {
    final base = locationSettingsForMotion(state);
    if (defaultTargetPlatform != TargetPlatform.android) return base;
    final interval = switch (state) {
      MotionState.driving => const Duration(seconds: 1),
      MotionState.walking => const Duration(seconds: 5),
      MotionState.stationary => const Duration(seconds: 30),
    };
    return AndroidSettings(
      accuracy: base.accuracy,
      distanceFilter: base.distanceFilter,
      intervalDuration: interval,
    );
  }

  Position _withSmoothedCoordinates(
    Position rawPosition,
    ProcessedGpsFix processed,
  ) {
    return Position.fromMap({
      ...rawPosition.toJson(),
      'latitude': processed.latitude,
      'longitude': processed.longitude,
    });
  }
}

class LocationAccessException implements Exception {
  final String message;
  final bool settingsRequired;

  const LocationAccessException(this.message, {this.settingsRequired = false});

  @override
  String toString() => message;
}
