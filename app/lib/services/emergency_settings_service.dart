import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demo_session.dart';

class EmergencySettingsService extends ChangeNotifier {
  EmergencySettingsService._();

  static final instance = EmergencySettingsService._();

  static const _autoCrashKey = 'emergency_auto_crash';
  static const _crashSoundCueKey = 'emergency_crash_sound_cue';
  static const _directCallKey = 'emergency_direct_call';
  static const _dryRunKey = 'emergency_dry_run';
  static const _tripTrackingKey = 'emergency_trip_tracking';
  static const _tripActiveKey = 'emergency_trip_active';

  bool _autoCrashDetectionEnabled = false;
  bool _crashSoundCueEnabled = false;
  bool _directCallEnabled = false;
  bool _dryRunEnabled = kDebugMode;
  bool _tripTrackingEnabled = false;
  bool _tripActive = false;
  bool _loaded = false;
  bool _demoMode = false;

  bool get autoCrashDetectionEnabled => _autoCrashDetectionEnabled;
  bool get crashSoundDetectionEnabled => _crashSoundCueEnabled;
  bool get directCallEnabled => _directCallEnabled;
  bool get dryRunEnabled => _demoMode || _dryRunEnabled;
  bool get tripTrackingEnabled => _tripTrackingEnabled;
  bool get isTripActive => _tripActive;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    if (DemoSession.instance.isActive) {
      enterDemoMode();
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    _autoCrashDetectionEnabled = preferences.getBool(_autoCrashKey) ?? false;
    _crashSoundCueEnabled = preferences.getBool(_crashSoundCueKey) ?? false;
    _directCallEnabled = preferences.getBool(_directCallKey) ?? false;
    _dryRunEnabled = kDebugMode || (preferences.getBool(_dryRunKey) ?? false);
    _tripTrackingEnabled = preferences.getBool(_tripTrackingKey) ?? false;
    _tripActive =
        _tripTrackingEnabled && (preferences.getBool(_tripActiveKey) ?? false);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setAutoCrashDetectionEnabled(bool value) async {
    _autoCrashDetectionEnabled = value;
    await _save(_autoCrashKey, value);
  }

  Future<void> setCrashSoundDetectionEnabled(bool value) async {
    _crashSoundCueEnabled = value;
    await _save(_crashSoundCueKey, value);
  }

  Future<void> setDirectCallEnabled(bool value) async {
    _directCallEnabled = value;
    await _save(_directCallKey, value);
  }

  Future<void> setDryRunEnabled(bool value) async {
    _dryRunEnabled = kDebugMode || value;
    await _save(_dryRunKey, _dryRunEnabled);
  }

  Future<void> setTripTrackingEnabled(bool value) async {
    _tripTrackingEnabled = value;
    await _save(_tripTrackingKey, value);
    if (!value && _tripActive) await endTrip();
  }

  Future<void> startTrip() async {
    if (!_tripTrackingEnabled || _tripActive) return;
    _tripActive = true;
    await _save(_tripActiveKey, true);
  }

  Future<void> endTrip() async {
    if (!_tripActive) return;
    _tripActive = false;
    await _save(_tripActiveKey, false);
  }

  void enterDemoMode() {
    _demoMode = true;
    _autoCrashDetectionEnabled = false;
    _crashSoundCueEnabled = false;
    _directCallEnabled = false;
    _dryRunEnabled = true;
    _tripTrackingEnabled = false;
    _tripActive = false;
    _loaded = true;
    notifyListeners();
  }

  void leaveDemoMode() {
    _demoMode = false;
    _loaded = false;
    _autoCrashDetectionEnabled = false;
    _crashSoundCueEnabled = false;
    _directCallEnabled = false;
    _dryRunEnabled = kDebugMode;
    _tripTrackingEnabled = false;
    _tripActive = false;
    notifyListeners();
  }

  Future<void> _save(String key, bool value) async {
    notifyListeners();
    if (_demoMode) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(key, value);
  }
}
