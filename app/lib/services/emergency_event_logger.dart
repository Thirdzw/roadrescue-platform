import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'demo_session.dart';

class EmergencyEventLogger {
  EmergencyEventLogger._();

  static const _storageKey = 'emergency_event_log';
  static const _maxEvents = 100;

  static Future<void> record({
    required String event,
    required String triggerType,
    DateTime? occurredAt,
    String? nearestCity,
    String? numberDialed,
  }) async {
    final entry = <String, Object?>{
      'timestamp': (occurredAt ?? DateTime.now()).toUtc().toIso8601String(),
      'event': event,
      'triggerType': triggerType,
      'nearestCity': nearestCity,
      'numberDialed': numberDialed,
    };
    debugPrint('Emergency event: ${jsonEncode(entry)}');
    if (DemoSession.instance.isActive) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final entries = preferences.getStringList(_storageKey) ?? <String>[];
      entries.add(jsonEncode(entry));
      await preferences.setStringList(
        _storageKey,
        entries.length <= _maxEvents
            ? entries
            : entries.sublist(entries.length - _maxEvents),
      );
    } catch (error) {
      debugPrint('Could not persist emergency event: $error');
    }
  }
}
