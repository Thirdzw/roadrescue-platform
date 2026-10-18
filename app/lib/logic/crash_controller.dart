import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/emergency_config.dart';
import '../services/crash_notification_service.dart';
import '../services/emergency_settings_service.dart';
import '../services/foreground_monitor_service.dart';
import '../services/sensor_tracker.dart';
import '../services/test_config.dart';
import '../services/demo_session.dart';
import '../services/emergency_alert_service.dart';

enum CrashState {
  idle,
  armed,
  impactSuspected,
  awaitingResponse,
  alertSent,
}

class CrashController extends ChangeNotifier with WidgetsBindingObserver {
  CrashController._();

  static final instance = CrashController._();

  final _stateController = StreamController<CrashState>.broadcast();
  StreamSubscription<double>? _soundSubscription;
  CrashState _state = CrashState.idle;
  bool _initialized = false;
  bool _isRunning = false;
  bool _soundCueEnabled = false;
  bool _dispatching = false;
  bool _testMode = false;
  bool _testAlertSent = false;
  String? _testError;
  int _secondsRemaining = crashResponseCountdownSeconds;
  String? _alertError;
  Timer? _demoCrashTimer;

  CrashState get state => _state;
  Stream<CrashState> get states => _stateController.stream;
  bool get isRunning => _isRunning;
  int get secondsRemaining => _secondsRemaining;
  bool get isDispatching => _dispatching;
  bool get isTestMode => _testMode;
  bool get testAlertSent => _testAlertSent;
  String? get alertError => _alertError;
  String? get testError => _testError;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    WidgetsBinding.instance.addObserver(this);
    sync();
  }

  Future<void> start() async {
    if (DemoSession.instance.isActive) {
      _isRunning = true;
      _soundCueEnabled =
          EmergencySettingsService.instance.crashSoundDetectionEnabled;
      _setState(CrashState.armed);
      return;
    }
    initialize();
    await _requestPermissions();
    await ForegroundMonitorService.start();
    _isRunning = true;
    _soundCueEnabled =
        EmergencySettingsService.instance.crashSoundDetectionEnabled;
    await _updateSoundCue();
    sync();
    notifyListeners();
  }

  Future<void> stop() async {
    if (_state == CrashState.awaitingResponse) {
      throw StateError(
        'Crash monitoring cannot stop while an emergency response is pending.',
      );
    }
    if (DemoSession.instance.isActive) {
      _demoCrashTimer?.cancel();
      _isRunning = false;
      _dispatching = false;
      _secondsRemaining = crashResponseCountdownSeconds;
      _alertError = null;
      _setState(CrashState.idle);
      return;
    }
    await _stopSoundCue();
    await ForegroundMonitorService.stop();
    _isRunning = false;
    _dispatching = false;
    _secondsRemaining = crashResponseCountdownSeconds;
    _alertError = null;
    _setState(CrashState.idle);
  }

  void sync() {
    if (DemoSession.instance.isActive) return;
    if (_isRunning) {
      FlutterForegroundTask.sendDataToTask({'type': 'sync'});
    } else {
      unawaited(_syncRunningState());
    }
  }

  Future<void> _syncRunningState() async {
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      _isRunning = true;
      FlutterForegroundTask.sendDataToTask({'type': 'sync'});
      notifyListeners();
    } catch (error) {
      debugPrint('Synchronizing crash-monitor service failed: $error');
    }
  }

  void cancelAlert() {
    if (_state != CrashState.awaitingResponse) return;
    if (DemoSession.instance.isActive) {
      _demoCrashTimer?.cancel();
      _secondsRemaining = crashResponseCountdownSeconds;
      _testMode = false;
      _setState(_isRunning ? CrashState.armed : CrashState.idle);
      return;
    }
    FlutterForegroundTask.sendDataToTask({'type': 'ok'});
  }

  Future<void> simulateCrash() async {
    if (DemoSession.instance.isActive) {
      if (!_isRunning) {
        throw StateError(
          'Enable automatic crash detection before simulating an alert.',
        );
      }
      _testMode = true;
      _testError = null;
      _testAlertSent = false;
      _secondsRemaining = 10;
      _setState(CrashState.awaitingResponse);
      _demoCrashTimer?.cancel();
      _demoCrashTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_secondsRemaining <= 1) {
          timer.cancel();
          unawaited(_finishDemoCrashAlert());
        } else {
          _secondsRemaining--;
          notifyListeners();
        }
      });
      return;
    }
    if (!kDebugMode || !TestConfig.enabled) {
      throw StateError('Crash simulation is debug-build only.');
    }
    if (!_isRunning) {
      throw StateError(
        'Enable automatic crash detection before simulating an alert.',
      );
    }
    _testError = null;
    FlutterForegroundTask.sendDataToTask({'type': 'debug_crash'});
  }

  Future<void> setTestMode(bool enabled) async {
    if (!kDebugMode) return;
    await TestConfig.set(enabled);
    if (_isRunning) {
      FlutterForegroundTask.sendDataToTask({
        'type': 'setTestMode',
        'enabled': enabled,
      });
    }
  }

  void sendTestFalseAlarm() {
    if (!kDebugMode || !_testAlertSent) return;
    _testError = null;
    FlutterForegroundTask.sendDataToTask({'type': 'falseAlarm'});
  }

  Future<void> setSoundCueEnabled(bool enabled) async {
    _soundCueEnabled = enabled;
    if (DemoSession.instance.isActive) return;
    await _updateSoundCue();
  }

  Future<void> _finishDemoCrashAlert() async {
    _dispatching = true;
    notifyListeners();
    try {
      await EmergencyAlertService.instance.sendCrashAlerts(testMode: true);
    } catch (error) {
      _alertError = 'Demo alert could not be recorded: $error';
    }
    _dispatching = false;
    _testMode = false;
    _secondsRemaining = crashResponseCountdownSeconds;
    _setState(CrashState.alertSent);
  }

  void _onTaskData(Object data) {
    if (data is! Map) return;
    final type = data['type'];
    if (type == 'status') {
      final stateName = data['state'];
      if (stateName is String) {
        final state =
            CrashState.values.where((value) => value.name == stateName);
        if (state.isNotEmpty) _setState(state.first);
      }
      final seconds = data['secondsRemaining'];
      if (seconds is num) _secondsRemaining = seconds.toInt();
      _dispatching = data['dispatching'] == true;
      _testMode = kDebugMode && data['testMode'] == true;
      _testAlertSent = kDebugMode && data['testAlertSent'] == true;
      final error = data['alertError'];
      _alertError = error is String && error.isNotEmpty ? error : null;
      _isRunning = true;
      notifyListeners();
    } else if (type == 'serviceStopped') {
      _isRunning = false;
      _setState(CrashState.idle);
    } else if (type == 'cancelled') {
      _dispatching = false;
      _testMode = false;
      _testAlertSent = false;
      _alertError = null;
      _secondsRemaining = crashResponseCountdownSeconds;
      notifyListeners();
    } else if (type == 'testError') {
      final message = data['message'];
      _testError = message is String ? message : 'Test alert failed.';
      notifyListeners();
    } else if (type == 'testFalseAlarmSent') {
      _testAlertSent = false;
      notifyListeners();
    } else if (type == 'dispatching') {
      _dispatching = true;
      _setState(CrashState.alertSent);
    }
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Automatic crash monitoring is Android-only.');
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on Location services to enable crash detection.');
    }
    var location = await Permission.locationWhenInUse.request();
    if (!location.isGranted) {
      throw StateError(
        'Allow location access so RoadRescue can estimate speed and identify a crash.',
      );
    }
    location = await Permission.locationAlways.request();
    if (!location.isGranted) {
      throw StateError(
        'Allow background location so crash monitoring continues with the screen off.',
      );
    }
    final sms = await Permission.sms.request();
    if (!sms.isGranted) {
      debugPrint(
        'SMS permission was declined. Crash monitoring remains enabled; SMS alerts will be skipped.',
      );
    }
    try {
      await CrashNotificationService.instance.requestFullScreenPermission();
    } catch (error) {
      debugPrint(
        'Full-screen crash notifications are unavailable; standard notifications remain enabled: $error',
      );
    }
  }

  Future<void> _updateSoundCue() async {
    if (!_soundCueEnabled ||
        !_isRunning ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        _soundSubscription != null) {
      if (!_soundCueEnabled ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        await _stopSoundCue();
      }
      return;
    }
    final permission = await Permission.microphone.status;
    if (!permission.isGranted) {
      debugPrint(
        'Optional crash sound cue is unavailable without microphone permission.',
      );
      return;
    }
    try {
      _soundSubscription = SensorTracker.instance.microphoneRms.listen(
        (rms) {
          if (rms >= crashSoundRmsThreshold) {
            FlutterForegroundTask.sendDataToTask({'type': 'loudSound'});
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Optional crash microphone stream failed: $error');
          unawaited(_stopSoundCue());
        },
      );
    } catch (error) {
      debugPrint('Optional crash microphone could not start: $error');
    }
  }

  Future<void> _stopSoundCue() async {
    await _soundSubscription?.cancel();
    _soundSubscription = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isRunning) sync();
      unawaited(_updateSoundCue());
    } else {
      unawaited(_stopSoundCue());
    }
  }

  void _setState(CrashState state) {
    if (_state == state) return;
    _state = state;
    _stateController.add(state);
    notifyListeners();
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopSoundCue());
    _stateController.close();
    super.dispose();
  }
}
