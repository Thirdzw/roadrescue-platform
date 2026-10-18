import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart'
    hide NotificationVisibility;
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../firebase_options.dart';
import '../logic/crash_fusion.dart';
import '../models/emergency_config.dart';
import 'emergency_alert_service.dart';
import 'emergency_settings_service.dart';
import 'gps_processing_pipeline.dart';
import 'test_config.dart';

class ForegroundMonitorService {
  static const _alarmNotificationId = 4102;
  static const _alarmChannelId = 'roadrescue_crash_alarm_v2';
  static const _checkNotificationId = 4104;

  static void initialize() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'roadrescue_crash_monitor',
        channelName: 'Crash detection',
        channelDescription: 'Keeps crash monitoring active during a trip.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        allowWakeLock: true,
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
      ),
    );
  }

  static Future<void> start() async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        await FlutterForegroundTask.isRunningService) {
      return;
    }
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      final requested =
          await FlutterForegroundTask.requestNotificationPermission();
      if (requested != NotificationPermission.granted) {
        throw StateError('Notification permission is required for monitoring.');
      }
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 4101,
      notificationTitle: 'RoadRescue crash protection is on',
      notificationText: 'Monitoring while you drive.',
      callback: startCrashMonitoringTask,
    );
    if (result is ServiceRequestFailure) {
      throw StateError('Could not start crash monitoring: ${result.error}');
    }
  }

  static Future<void> stop() async {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

@pragma('vm:entry-point')
void startCrashMonitoringTask() {
  FlutterForegroundTask.setTaskHandler(_CrashMonitoringTaskHandler());
}

class _CrashMonitoringTaskHandler extends TaskHandler {
  final CrashFusion _fusion = CrashFusion();
  final GpsProcessingPipeline _gpsPipeline = GpsProcessingPipeline();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _alarmPlayer = AudioPlayer();

  StreamSubscription<AccelerometerEvent>? _accelerometer;
  StreamSubscription<Position>? _location;
  StreamSubscription<GyroscopeEvent>? _gyroscope;
  StreamSubscription<BarometerEvent>? _barometer;
  Timer? _verification;
  Timer? _vibration;
  SharedPreferences? _preferences;
  Position? _lastPosition;
  DateTime? _lastSpeedOverThreshold;
  DateTime? _quietUntil;
  CrashAssessment? _assessment;
  String _state = 'idle';
  DateTime? _countdownEndsAt;
  int _lastPublishedSeconds = -1;
  int _verificationAttempts = 0;
  bool _alerting = false;
  bool _dispatching = false;
  bool _isTestAlert = false;
  bool _testAlertSent = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _preferences = await SharedPreferences.getInstance();
    await _preferences!.reload();
    await EmergencySettingsService.instance.load();
    if (kDebugMode && TestConfig.enabled) {
      try {
        await TestConfig.loadContacts();
      } catch (error) {
        debugPrint('Loading debug crash-test contacts failed: $error');
      }
    }
    if (!(_preferences!.getBool('emergency_auto_crash') ?? false)) {
      FlutterForegroundTask.sendDataToMain({'type': 'state', 'state': 'idle'});
      await FlutterForegroundTask.stopService();
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.android,
        );
      }
    } catch (error) {
      debugPrint('Initializing Firebase in crash service failed: $error');
    }

    await _initializeNotifications();
    await _restoreAlert();
    _startSensors();
    _publishState();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _checkArmedWindow(timestamp);
    if (_alerting) _publishCountdown();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _accelerometer?.cancel();
    await _location?.cancel();
    await _gyroscope?.cancel();
    await _barometer?.cancel();
    _verification?.cancel();
    _vibration?.cancel();
    await _alarmPlayer.stop();
    await _alarmPlayer.dispose();
    try {
      await Vibration.cancel();
    } catch (error) {
      debugPrint('Stopping crash-service vibration failed: $error');
    }
    FlutterForegroundTask.sendDataToMain({'type': 'serviceStopped'});
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      switch (data['type']) {
        case 'sync':
          _publishState();
          break;
        case 'ok':
          if (_alerting) unawaited(_cancelAlert());
          break;
        case 'loudSound':
          _fusion.onLoudSound();
          break;
        case 'debug_crash':
          if (kDebugMode) {
            unawaited(_startTestCrash());
          } else {
            FlutterForegroundTask.sendDataToMain({
              'type': 'testError',
              'message': 'Enable debug test mode and add a test contact first.',
            });
          }
          break;
        case 'falseAlarm':
          if (kDebugMode && _testAlertSent) {
            unawaited(_sendTestFalseAlarm());
          }
          break;
        case 'setTestMode':
          final enabled = data['enabled'] == true;
          unawaited(_setTestMode(enabled));
          break;
      }
    } else if (data == 'sync') {
      _publishState();
    } else if (data == 'ok' && _alerting) {
      unawaited(_cancelAlert());
    } else if (data == 'debug_crash' && kDebugMode) {
      unawaited(_startTestCrash());
    }
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() => _publishState();

  @override
  void onNotificationDismissed() {}

  Future<void> _initializeNotifications() async {
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        ForegroundMonitorService._alarmChannelId,
        'Crash alarm',
        description: 'Rings and displays the active crash response prompt.',
        importance: Importance.max,
        playSound: false,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'roadrescue_crash_check',
        'Crash check',
        description: 'Low-priority checks for possible impacts.',
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
      ),
    );
  }

  Future<void> _restoreAlert() async {
    final prefs = _preferences!;
    final endMilliseconds = prefs.getInt('crash_alert_end_epoch_ms');
    final assessmentJson = prefs.getString('crash_alert_assessment');
    if (endMilliseconds == null || assessmentJson == null) return;

    try {
      _assessment = CrashAssessment.fromMap(
        jsonDecode(assessmentJson) as Map<String, dynamic>,
      );
      final persistedTestMode = prefs.getBool('crash_alert_test_mode') ?? false;
      if (persistedTestMode && !kDebugMode) {
        throw const FormatException(
          'A debug test alert cannot be restored in a release build.',
        );
      }
      _isTestAlert = persistedTestMode;
      _countdownEndsAt = DateTime.fromMillisecondsSinceEpoch(endMilliseconds);
      _alerting = true;
      _state = 'awaitingResponse';
      await _startAlarm();
      if (!_alerting) return;
      _publishCountdown();
    } catch (error) {
      debugPrint('Restoring pending crash alert failed: $error');
      await prefs.remove('crash_alert_end_epoch_ms');
      await prefs.remove('crash_alert_assessment');
      await prefs.remove('crash_alert_test_mode');
    }
  }

  void _startSensors() {
    _accelerometer = accelerometerEventStream(
      samplingPeriod: crashSensorSamplingPeriod,
    ).listen(
      _onAcceleration,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Crash-service accelerometer stream failed: $error');
      },
    );
    _location = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'RoadRescue crash protection',
          notificationText: 'Monitoring movement while driving.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
    ).listen(
      _onPosition,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Crash-service GPS stream failed: $error');
      },
    );
    try {
      _gyroscope = gyroscopeEventStream(
        samplingPeriod: crashSensorSamplingPeriod,
      ).listen(
        (event) => _fusion.onGyro(
          math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z),
        ),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Optional crash-service gyroscope unavailable: $error');
        },
      );
    } catch (error) {
      debugPrint('Optional crash-service gyroscope could not start: $error');
    }
    try {
      _barometer = barometerEventStream(
        samplingPeriod: const Duration(milliseconds: 100),
      ).listen(
        _onPressure,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Optional crash-service barometer unavailable: $error');
        },
      );
    } catch (error) {
      debugPrint('Optional crash-service barometer could not start: $error');
    }
  }

  void _onPosition(Position position) {
    final speedMetersPerSecond =
        position.speed.isFinite && position.speed > 0 ? position.speed : 0.0;
    final mph = speedMetersPerSecond * metersPerSecondToMilesPerHour;
    _fusion.onSpeed(mph, position.timestamp);
    final processed = _gpsPipeline.process(GpsFix.fromPosition(position));
    if (processed != null) {
      _lastPosition = Position.fromMap({
        ...position.toJson(),
        'latitude': processed.latitude,
        'longitude': processed.longitude,
      });
    }
    if (mph > CrashFusionTuning.armMph) {
      _lastSpeedOverThreshold = position.timestamp;
      if (_state == 'idle') _setState('armed');
    }
    _checkArmedWindow(DateTime.now());
  }

  void _onAcceleration(AccelerometerEvent event) {
    if (_alerting || _dispatching) return;
    if (_state != 'armed' && _state != 'impactSuspected') return;
    if (_quietUntil != null && DateTime.now().isBefore(_quietUntil!)) return;
    final g = math.sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        ) /
        gravityMetersPerSecondSquared;
    final started = _fusion.onAccel(g);
    if (started && _state == 'armed') {
      _verificationAttempts = 0;
      _setState('impactSuspected');
      _verifyImpact();
    }
  }

  void _onPressure(BarometerEvent event) {
    final previous = _previousPressureHpa;
    _previousPressureHpa = event.pressure;
    if ((_state == 'armed' || _state == 'impactSuspected') &&
        previous != null &&
        (event.pressure - previous).abs() >= crashBarometerPressureChangeHpa) {
      _fusion.onPressureSpike();
    }
  }

  double? _previousPressureHpa;

  void _verifyImpact() {
    _verification?.cancel();
    _verification = Timer.periodic(crashConfirmationDelay, (timer) {
      _verificationAttempts++;
      final assessment = _fusion.assess();
      if (assessment != null && assessment.action != CrashAction.ignore) {
        timer.cancel();
        unawaited(_handleAssessment(assessment));
      } else if (_verificationAttempts >= crashVerificationAttempts) {
        timer.cancel();
        _fusion.reset();
        _setState(_withinArmedWindow ? 'armed' : 'idle');
      }
    });
  }

  Future<void> _handleAssessment(
    CrashAssessment assessment, {
    bool testMode = false,
  }) async {
    debugPrint(
      'Crash assessment ${assessment.action.name}: '
      '${assessment.score}/9 ${assessment.summary()}',
    );
    _fusion.reset();
    if (assessment.action == CrashAction.silentCheck) {
      await _showSilentCheck(assessment);
      _setState(_withinArmedWindow ? 'armed' : 'idle');
      return;
    }
    _assessment = assessment;
    _isTestAlert = testMode;
    _alerting = true;
    _state = 'awaitingResponse';
    _countdownEndsAt = DateTime.now().add(
      Duration(seconds: assessment.countdownSeconds),
    );
    await _persistPendingAlert();
    await _startAlarm();
    _publishState();
  }

  Future<void> _startTestCrash() async {
    if (_alerting || _dispatching || !kDebugMode) return;

    try {
      await TestConfig.loadContacts();
      if (!TestConfig.enabled) {
        FlutterForegroundTask.sendDataToMain({
          'type': 'testError',
          'message': 'Enable debug test mode before simulating an alert.',
        });
        return;
      }
      if (TestConfig.testContacts.isEmpty) {
        FlutterForegroundTask.sendDataToMain({
          'type': 'testError',
          'message': 'Add at least one debug test contact first.',
        });
        return;
      }
      final assessment = CrashAssessment(
        action: CrashAction.shortCountdown,
        severity: Severity.severe,
        score: 9,
        peakG: CrashFusionTuning.severeG,
        speedBeforeMph: 50,
        speedNowMph: 0,
        evidence: Evidence.values.toSet(),
      );
      await _handleAssessment(assessment, testMode: true);
    } catch (error) {
      debugPrint('Starting simulated crash alert failed: $error');
      FlutterForegroundTask.sendDataToMain({
        'type': 'testError',
        'message': 'Could not start test alert: $error',
      });
    }
  }

  Future<void> _setTestMode(bool enabled) async {
    if (!kDebugMode) return;
    await TestConfig.set(enabled);
    await TestConfig.loadContacts();
    _publishState();
  }

  Future<void> _showSilentCheck(CrashAssessment assessment) async {
    try {
      await _notifications.show(
        id: ForegroundMonitorService._checkNotificationId,
        title: 'Did something happen?',
        body: assessment.summary(),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'roadrescue_crash_check',
            'Crash check',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            category: AndroidNotificationCategory.status,
            autoCancel: true,
            playSound: false,
          ),
        ),
      );
    } catch (error) {
      debugPrint('Displaying the low-priority crash check failed: $error');
    }
  }

  Future<void> _persistPendingAlert() async {
    final prefs = _preferences;
    final assessment = _assessment;
    final endsAt = _countdownEndsAt;
    if (prefs == null || assessment == null || endsAt == null) return;
    await prefs.setInt(
      'crash_alert_end_epoch_ms',
      endsAt.millisecondsSinceEpoch,
    );
    await prefs.setString(
      'crash_alert_assessment',
      jsonEncode(assessment.toMap()),
    );
    await prefs.setBool('crash_alert_test_mode', _isTestAlert);
  }

  Future<void> _startAlarm() async {
    final assessment = _assessment;
    if (!_alerting || assessment == null) return;
    await _showAlarmNotification(assessment.countdownSeconds);
    try {
      await _alarmPlayer.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gainTransient,
          ),
        ),
      );
      await _alarmPlayer.setReleaseMode(ReleaseMode.loop);
      await _alarmPlayer.play(
        BytesSource(_createAlarmTone(), mimeType: 'audio/wav'),
        volume: 1,
      );
    } catch (error) {
      debugPrint('Playing the crash alarm tone failed: $error');
    }
    _vibration?.cancel();
    _vibration = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_alerting) return;
      unawaited(
        Vibration.vibrate(duration: 1200, amplitude: 255).catchError(
          (Object error) {
            debugPrint('Crash alert vibration failed: $error');
          },
        ),
      );
    });
    unawaited(
      Vibration.vibrate(duration: 1200, amplitude: 255).catchError(
        (Object error) {
          debugPrint('Crash alert vibration failed: $error');
        },
      ),
    );
  }

  Future<void> _showAlarmNotification(int secondsRemaining) async {
    final assessment = _assessment;
    if (assessment == null) return;
    try {
      await _notifications.show(
        id: ForegroundMonitorService._alarmNotificationId,
        title: _isTestAlert
            ? 'TEST - Crash detected, Are you OK?'
            : 'Crash detected, Are you OK?',
        body: '$secondsRemaining seconds to cancel. '
            '${assessment.summary()}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            ForegroundMonitorService._alarmChannelId,
            'Crash alarm',
            channelDescription:
                'Rings and displays the active crash response prompt.',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            fullScreenIntent: true,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            enableVibration: true,
            playSound: false,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        ),
        payload: 'crash_prompt',
      );
    } catch (error) {
      debugPrint('Displaying full-screen crash alert failed: $error');
    }
  }

  void _publishCountdown() {
    final end = _countdownEndsAt;
    if (!_alerting || end == null) return;
    final seconds =
        math.max(0, end.difference(DateTime.now()).inSeconds).toInt();
    if (seconds != _lastPublishedSeconds) {
      _lastPublishedSeconds = seconds;
      _publishState(secondsRemaining: seconds);
      if (seconds <= 0) {
        unawaited(_dispatchAlert());
      } else {
        unawaited(_showAlarmNotification(seconds));
      }
    }
  }

  void _checkArmedWindow(DateTime now) {
    if (_state != 'armed' || _withinArmedWindowAt(now)) return;
    _setState('idle');
  }

  bool get _withinArmedWindow => _withinArmedWindowAt(DateTime.now());

  bool _withinArmedWindowAt(DateTime now) {
    final lastSpeed = _lastSpeedOverThreshold;
    return lastSpeed != null &&
        now.difference(lastSpeed) < crashArmedGracePeriod;
  }

  void _setState(String state) {
    if (_state == state) return;
    _state = state;
    _publishState();
  }

  void _publishState({int? secondsRemaining, String? error}) {
    final remaining = secondsRemaining ??
        (_alerting && _countdownEndsAt != null
            ? math
                .max(
                  0,
                  _countdownEndsAt!.difference(DateTime.now()).inSeconds,
                )
                .toInt()
            : 0);
    FlutterForegroundTask.sendDataToMain({
      'type': 'status',
      'state': _state,
      'alerting': _alerting,
      'dispatching': _dispatching,
      'testMode': kDebugMode && _isTestAlert,
      'testAlertSent': kDebugMode && _testAlertSent,
      'secondsRemaining': remaining,
      'severity': _assessment?.severity.name ?? 'minor',
      'summary': _assessment?.summary() ?? '',
      'alertError': error ?? '',
    });
  }

  Future<void> _cancelAlert() async {
    _alerting = false;
    _vibration?.cancel();
    await _alarmPlayer.stop();
    try {
      await Vibration.cancel();
    } catch (error) {
      debugPrint('Stopping crash alert vibration failed: $error');
    }
    await _notifications.cancel(
        id: ForegroundMonitorService._alarmNotificationId);
    await _preferences?.remove('crash_alert_end_epoch_ms');
    await _preferences?.remove('crash_alert_assessment');
    await _preferences?.remove('crash_alert_test_mode');
    _assessment = null;
    _isTestAlert = false;
    _testAlertSent = false;
    _countdownEndsAt = null;
    _lastPublishedSeconds = -1;
    _quietUntil = DateTime.now().add(crashDetectionCooldown);
    _setState(_withinArmedWindow ? 'armed' : 'idle');
    FlutterForegroundTask.sendDataToMain({'type': 'cancelled'});
  }

  Future<void> _dispatchAlert() async {
    if (_dispatching || !_alerting) return;
    _dispatching = true;
    _alerting = false;
    _vibration?.cancel();
    await _alarmPlayer.stop();
    try {
      await Vibration.cancel();
    } catch (error) {
      debugPrint('Stopping crash alert vibration failed: $error');
    }
    await _notifications.cancel(
        id: ForegroundMonitorService._alarmNotificationId);
    _state = 'alertSent';
    _publishState();
    String? errorMessage;
    try {
      await EmergencyAlertService.instance.sendCrashAlerts(
        position: _freshLastPosition,
        evidenceScore: _assessment?.evidenceScore,
        crashSummary: _assessment?.summary(),
        testMode: kDebugMode && _isTestAlert,
      );
    } catch (error) {
      errorMessage = error.toString();
      debugPrint('Background crash-alert dispatch failed: $error');
    } finally {
      await _preferences?.remove('crash_alert_end_epoch_ms');
      await _preferences?.remove('crash_alert_assessment');
      await _preferences?.remove('crash_alert_test_mode');
      _testAlertSent = kDebugMode && _isTestAlert;
      _dispatching = false;
      _publishState(error: errorMessage);
    }
  }

  Future<void> _sendTestFalseAlarm() async {
    if (!kDebugMode || !_testAlertSent) return;
    try {
      await EmergencyAlertService.instance.sendTestFalseAlarmSms();
      _testAlertSent = false;
      FlutterForegroundTask.sendDataToMain({'type': 'testFalseAlarmSent'});
      _publishState();
    } catch (error) {
      debugPrint('Sending test false-alarm SMS failed: $error');
      FlutterForegroundTask.sendDataToMain({
        'type': 'testError',
        'message': 'Test false-alarm follow-up failed: $error',
      });
    }
  }

  Position? get _freshLastPosition {
    final position = _lastPosition;
    if (position == null ||
        DateTime.now().difference(position.timestamp) >
            crashLastKnownPositionMaxAge) {
      return null;
    }
    return position;
  }

  Uint8List _createAlarmTone() {
    const sampleRate = 22050;
    const durationSeconds = 2;
    const sampleCount = sampleRate * durationSeconds;
    final bytes = Uint8List(44 + sampleCount * 2);
    final header = ByteData.sublistView(bytes);

    void writeAscii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        bytes[offset + index] = value.codeUnitAt(index);
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, bytes.length - 8, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, sampleCount * 2, Endian.little);
    for (var sample = 0; sample < sampleCount; sample++) {
      final phase = sample / sampleRate;
      final frequency = phase % 1 < 0.5 ? 880.0 : 660.0;
      final value =
          (math.sin(2 * math.pi * frequency * phase) * 0.7 * 32767).round();
      header.setInt16(44 + sample * 2, value, Endian.little);
    }
    return bytes;
  }
}
