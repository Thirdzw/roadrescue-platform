import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/maintenance_schedule.dart';
import 'demo_session.dart';
import 'gps_processing_pipeline.dart';
import 'location_service.dart';

const defaultMaintenanceIntervalKm = 5000.0;
const defaultMaintenanceIntervalDays = 180;
const maximumMaintenanceGpsAccuracyMeters = gpsMaximumAccuracyMeters;
const maximumMaintenanceSampleGap = Duration(minutes: 2);

class MaintenanceReminderService extends ChangeNotifier {
  MaintenanceReminderService._();

  static final instance = MaintenanceReminderService._();

  static const _serviceOdometerKey = 'maintenance_service_odometer_km';
  static const _serviceDateKey = 'maintenance_service_date';
  static const _serviceIntervalKey = 'maintenance_service_interval_km';
  static const _distanceSinceServiceKey = 'maintenance_gps_distance_since_km';

  StreamSubscription<Position>? _positionSubscription;
  Position? _previousPosition;
  DateTime? _lastServiceDate;
  double? _lastServiceOdometerKm;
  double _serviceIntervalKm = defaultMaintenanceIntervalKm;
  double _gpsDistanceSinceServiceKm = 0;
  Future<void> _persistTail = Future<void>.value();
  bool _initialized = false;
  bool _demoMode = false;
  DateTime? _savedServiceDate;
  double? _savedServiceOdometerKm;
  double? _savedServiceIntervalKm;
  double? _savedGpsDistanceSinceServiceKm;
  bool _wasInitialized = false;

  bool get isInitialized => _initialized;
  bool get hasServiceRecord =>
      _lastServiceDate != null && _lastServiceOdometerKm != null;
  DateTime? get lastServiceDate => _lastServiceDate;
  double? get lastServiceOdometerKm => _lastServiceOdometerKm;
  double get serviceIntervalKm => _serviceIntervalKm;
  double get gpsDistanceSinceServiceKm => _gpsDistanceSinceServiceKm;
  MaintenanceSchedule? get schedule => hasServiceRecord
      ? MaintenanceSchedule(
          lastServiceOdometerKm: _lastServiceOdometerKm!,
          lastServiceDate: _lastServiceDate!,
          distanceSinceServiceKm: _gpsDistanceSinceServiceKm,
          serviceIntervalKm: _serviceIntervalKm,
          serviceIntervalDays: defaultMaintenanceIntervalDays,
        )
      : null;
  double? get estimatedOdometerKm => schedule?.estimatedOdometerKm;
  double? get nextServiceOdometerKm => schedule?.nextServiceOdometerKm;

  bool get isDue => schedule?.isDueAt(DateTime.now()) ?? false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (DemoSession.instance.isActive) {
      enterDemoMode();
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    _lastServiceOdometerKm = preferences.getDouble(_serviceOdometerKey);
    final serviceDate = preferences.getString(_serviceDateKey);
    _lastServiceDate =
        serviceDate == null ? null : DateTime.tryParse(serviceDate);
    _serviceIntervalKm = preferences.getDouble(_serviceIntervalKey) ??
        defaultMaintenanceIntervalKm;
    _gpsDistanceSinceServiceKm =
        preferences.getDouble(_distanceSinceServiceKey) ?? 0;
    _positionSubscription = LocationService.instance.positions.listen(
      _onPosition,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Maintenance GPS distance tracking failed: $error');
      },
    );
    _initialized = true;
    notifyListeners();
  }

  void enterDemoMode() {
    if (_demoMode) return;
    _savedServiceDate = _lastServiceDate;
    _savedServiceOdometerKm = _lastServiceOdometerKm;
    _savedServiceIntervalKm = _serviceIntervalKm;
    _savedGpsDistanceSinceServiceKm = _gpsDistanceSinceServiceKm;
    _wasInitialized = _initialized;
    _demoMode = true;
    _lastServiceDate = DateTime.now().subtract(const Duration(days: 60));
    _lastServiceOdometerKm = 100000;
    _serviceIntervalKm = defaultMaintenanceIntervalKm;
    _gpsDistanceSinceServiceKm = 1200;
    _previousPosition = null;
    _initialized = true;
    notifyListeners();
  }

  void leaveDemoMode() {
    if (!_demoMode) return;
    _demoMode = false;
    _lastServiceDate = _savedServiceDate;
    _lastServiceOdometerKm = _savedServiceOdometerKm;
    _serviceIntervalKm =
        _savedServiceIntervalKm ?? defaultMaintenanceIntervalKm;
    _gpsDistanceSinceServiceKm = _savedGpsDistanceSinceServiceKm ?? 0;
    _previousPosition = null;
    _initialized = _wasInitialized;
    _savedServiceDate = null;
    _savedServiceOdometerKm = null;
    _savedServiceIntervalKm = null;
    _savedGpsDistanceSinceServiceKm = null;
    notifyListeners();
  }

  Future<void> recordService({
    required double odometerKm,
    required DateTime serviceDate,
    required double intervalKm,
  }) async {
    if (!odometerKm.isFinite || odometerKm < 0) {
      throw ArgumentError.value(odometerKm, 'odometerKm');
    }
    if (!intervalKm.isFinite || intervalKm <= 0) {
      throw ArgumentError.value(intervalKm, 'intervalKm');
    }
    if (serviceDate.isAfter(DateTime.now())) {
      throw ArgumentError.value(serviceDate, 'serviceDate');
    }

    _lastServiceOdometerKm = odometerKm;
    _lastServiceDate = serviceDate;
    _serviceIntervalKm = intervalKm;
    _gpsDistanceSinceServiceKm = 0;
    _previousPosition = LocationService.instance.isTracking
        ? LocationService.instance.lastPosition
        : null;
    await _persist();
    notifyListeners();
  }

  Future<void> disposeService() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void _onPosition(Position position) {
    if (!LocationService.instance.isTracking) {
      _previousPosition = null;
      return;
    }
    if (position.accuracy > maximumMaintenanceGpsAccuracyMeters) {
      _previousPosition = null;
      return;
    }

    final previous = _previousPosition;
    _previousPosition = position;
    if (previous == null ||
        previous.accuracy > maximumMaintenanceGpsAccuracyMeters) {
      return;
    }

    final elapsed = position.timestamp.difference(previous.timestamp);
    if (elapsed <= Duration.zero || elapsed > maximumMaintenanceSampleGap) {
      return;
    }
    final distanceMeters = haversineMeters(
      previous.latitude,
      previous.longitude,
      position.latitude,
      position.longitude,
    );
    if (!distanceMeters.isFinite || distanceMeters <= 0) return;

    final maximumPlausibleDistance =
        elapsed.inSeconds * 60.0 + previous.accuracy + position.accuracy;
    if (distanceMeters > maximumPlausibleDistance) return;

    _gpsDistanceSinceServiceKm += distanceMeters / 1000;
    unawaited(
      _persist().catchError((Object error, StackTrace stackTrace) {
        debugPrint('Saving GPS maintenance distance failed: $error');
      }),
    );
    notifyListeners();
  }

  Future<void> _persist() {
    if (_demoMode) return Future<void>.value();
    _persistTail =
        _persistTail.catchError((Object error, StackTrace stackTrace) {
      debugPrint('Earlier maintenance reminder save failed: $error');
    }).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      final odometer = _lastServiceOdometerKm;
      final serviceDate = _lastServiceDate;
      if (odometer != null && serviceDate != null) {
        await preferences.setDouble(_serviceOdometerKey, odometer);
        await preferences.setString(
          _serviceDateKey,
          serviceDate.toIso8601String(),
        );
      }
      await preferences.setDouble(_serviceIntervalKey, _serviceIntervalKm);
      await preferences.setDouble(
        _distanceSinceServiceKey,
        _gpsDistanceSinceServiceKm,
      );
    });
    return _persistTail;
  }
}
