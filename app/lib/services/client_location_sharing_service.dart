import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'firestore_service.dart';
import 'demo_session.dart';
import 'location_service.dart';

class ClientLocationSharingService {
  ClientLocationSharingService._();

  static final instance = ClientLocationSharingService._();

  static const _maximumAccuracyMeters = 100.0;
  static const _distanceFilterMeters = 0;
  static const _updateInterval = Duration(seconds: 10);

  final ValueNotifier<String?> error = ValueNotifier(null);
  StreamSubscription<Position>? _subscription;
  String? _jobId;
  Future<void>? _starting;
  Future<void> _pendingUpload = Future<void>.value();
  int _generation = 0;
  bool _demoSharing = false;

  String? get activeJobId => _jobId;
  bool get isSharing => _subscription != null || _demoSharing;

  Future<void> start(String jobId) async {
    if (_jobId == jobId && isSharing) return;
    if (_jobId == jobId && _starting != null) {
      await _starting;
      return;
    }
    await stopLocal();
    final generation = ++_generation;
    _jobId = jobId;
    error.value = null;
    final startTask = _start(jobId, generation);
    _starting = startTask;
    try {
      await startTask;
    } catch (_) {
      if (_jobId == jobId) _jobId = null;
      rethrow;
    } finally {
      if (identical(_starting, startTask)) _starting = null;
    }
  }

  Future<void> stopLocal({String? jobId}) async {
    if (jobId != null && _jobId != jobId) return;
    _generation++;
    final subscription = _subscription;
    _subscription = null;
    _demoSharing = false;
    _jobId = null;
    await subscription?.cancel();
    await _pendingUpload;
  }

  Future<void> _start(String jobId, int generation) async {
    if (DemoSession.instance.isActive) {
      final position = await LocationService.instance.getCurrentLocation();
      if (_jobId != jobId || _generation != generation) return;
      await _publish(jobId, position);
      if (_jobId == jobId && _generation == generation) {
        _demoSharing = true;
      }
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on Location services to share your location.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw StateError(
          'Location permission is required to share live location.');
    }

    final initial = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    if (_jobId != jobId || _generation != generation) return;
    await _publish(jobId, initial);
    if (_jobId != jobId || _generation != generation) return;

    final settings = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: _distanceFilterMeters,
            intervalDuration: _updateInterval,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'RoadRescue is sharing your location',
              notificationText:
                  'Your assigned rescue provider can see your live location.',
              enableWakeLock: false,
              setOngoing: true,
            ),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: _distanceFilterMeters,
          );
    _subscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (position) => unawaited(_queuePublish(jobId, position)),
      onError: (Object exception, StackTrace stackTrace) {
        if (_jobId != jobId || _generation != generation) return;
        error.value = 'Live location updates stopped: $exception';
        debugPrint('Client live location stream failed: $exception');
        unawaited(stopLocal(jobId: jobId));
      },
    );
  }

  Future<void> _queuePublish(String jobId, Position position) {
    final next = _pendingUpload.then((_) => _publish(jobId, position));
    _pendingUpload = next;
    return next;
  }

  Future<void> _publish(String jobId, Position position) async {
    if (_jobId != jobId) return;
    if (!position.latitude.isFinite ||
        !position.longitude.isFinite ||
        !position.accuracy.isFinite ||
        position.accuracy > _maximumAccuracyMeters) {
      error.value =
          'Waiting for a more accurate GPS fix before sharing your location.';
      return;
    }
    try {
      await FirestoreService().updateJobLiveLocation(
        jobId: jobId,
        position: position,
      );
      error.value = null;
    } catch (exception) {
      error.value = 'Could not update your shared location: $exception';
      debugPrint('Uploading client live location failed: $exception');
    }
  }
}
