import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/contact.dart';
import '../models/crash_evidence_score.dart';
import '../models/emergency_config.dart';
import '../services/emergency_settings_service.dart';
import 'firestore_service.dart';
import 'location_service.dart';
import 'sensor_tracker.dart';
import 'test_config.dart';
import 'demo_session.dart';

class EmergencyAlertService {
  EmergencyAlertService._();

  static final instance = EmergencyAlertService._();

  Future<void> sendTestFalseAlarmSms() async {
    if (DemoSession.instance.isActive) {
      debugPrint('Demo mode: simulated false-alarm message; no SMS was sent.');
      return;
    }
    if (!kDebugMode) {
      throw UnsupportedError('Test follow-up SMS is debug-build only.');
    }
    await TestConfig.loadContacts();
    final contacts = TestConfig.testContacts;
    if (contacts.isEmpty) {
      throw StateError('No debug test contacts are configured.');
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Debug test SMS is Android-only.');
    }
    final permission = await Permission.sms.status;
    if (!permission.isGranted) {
      throw StateError('SMS permission is needed for the test follow-up SMS.');
    }
    final userName = await FirestoreService().currentUserName();
    final phones = <String>{};
    for (final contact in contacts) {
      final phone = contact.phone.trim();
      if (phone.isEmpty || !phones.add(phone)) continue;
      try {
        await _sendSms(
          phone: phone,
          contactName: contact.name,
          message: 'TEST - FALSE ALARM: $userName is OK. '
              'This was a RoadRescue test alert; no emergency response is needed.',
        );
      } catch (error) {
        debugPrint('Test false-alarm SMS to ${contact.name} failed: $error');
      }
    }
  }

  Future<void> sendCrashAlerts({
    Position? position,
    CrashEvidenceScore? evidenceScore,
    String? crashSummary,
    bool testMode = false,
  }) async {
    if (DemoSession.instance.isActive) {
      final demoPosition = position ??
          await LocationService.instance.getCurrentLocation(
            requestPermission: false,
          );
      await FirestoreService().createAutomaticCrashAlert(
        recipientUserIds: const [],
        message: 'Demo crash alert simulation',
        position: demoPosition,
        evidenceScore: evidenceScore ?? const CrashEvidenceScore(),
        test: true,
      );
      debugPrint(
        'Demo mode: simulated crash alert; no SMS or push was sent.',
      );
      return;
    }
    if (testMode && !TestConfig.enabled) {
      throw StateError('Test-mode alerts are disabled in this build.');
    }
    if (testMode) await TestConfig.loadContacts();
    var alertPosition = position;
    if (alertPosition == null) {
      try {
        alertPosition = await SensorTracker.instance.currentPosition();
      } catch (error) {
        final lastPosition = SensorTracker.instance.lastPosition;
        if (lastPosition == null ||
            DateTime.now().difference(lastPosition.timestamp) >
                crashLastKnownPositionMaxAge) {
          rethrow;
        }
        debugPrint(
            'Fresh crash location unavailable; using last GPS fix: $error');
        alertPosition = lastPosition;
      }
    }

    final firestore = FirestoreService();
    final userName = await firestore.currentUserName();
    List<Contact> contacts;
    if (testMode) {
      contacts = TestConfig.testContacts;
      if (contacts.isEmpty) {
        throw StateError(
          'Add at least one debug test contact before simulating a crash.',
        );
      }
    } else {
      try {
        contacts = await firestore.loadEmergencyContacts();
      } catch (error) {
        debugPrint('Could not load crash alert contacts: $error');
        contacts = const [];
      }
    }

    final summary = crashSummary?.trim();
    final testPrefix = testMode ? 'TEST - EMERGENCY: ' : '';
    final message = '$testPrefix$userName may have been in a crash'
        '${summary == null || summary.isEmpty ? '' : ' ($summary)'}. '
        'Their location: https://maps.google.com/?q='
        '${alertPosition.latitude},${alertPosition.longitude}';
    final score = evidenceScore ?? const CrashEvidenceScore();
    final recipients = contacts
        .where((contact) => contact.type == ContactType.circleMember)
        .map((contact) => contact.userId?.trim())
        .whereType<String>()
        .where((userId) => userId.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (!testMode && EmergencySettingsService.instance.dryRunEnabled) {
      debugPrint('Crash-alert dry run. Message: $message');
      debugPrint(
        'Crash-alert sensor evidence (${score.total} points): '
        '${score.toMap()}',
      );
      for (final contact in contacts) {
        debugPrint('Crash-alert dry run recipient: ${contact.phone}');
      }
      debugPrint('Crash-alert dry run push user IDs: $recipients');
      return;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final permission = await Permission.sms.status;
      if (!permission.isGranted) {
        debugPrint(
            'SMS crash alerts skipped: SEND_SMS permission is not granted.');
      } else {
        final sentPhones = <String>{};
        for (final contact in contacts) {
          final phone = contact.phone.trim();
          if (phone.isEmpty || !sentPhones.add(phone)) continue;
          try {
            await _sendSms(
              phone: phone,
              contactName: contact.name,
              message: message,
            );
          } catch (error) {
            debugPrint('Crash SMS to ${contact.name} failed: $error');
          }
        }
      }
    } else {
      debugPrint('SMS crash alerts are only supported on Android.');
    }

    try {
      await firestore.createAutomaticCrashAlert(
        recipientUserIds: recipients,
        message: message,
        position: alertPosition,
        evidenceScore: score,
        test: testMode,
      );
    } catch (error) {
      debugPrint('Crash alert could not be submitted to Firebase: $error');
      if (testMode) rethrow;
    }
  }

  Future<void> _sendSms({
    required String phone,
    required String contactName,
    required String message,
  }) {
    return Telephony.instance.sendSms(
      to: phone,
      message: message,
      isMultipart: true,
      statusListener: (status) {
        if (status == SendStatus.SENT) {
          debugPrint(
            'Android SMS sent-status callback received for $contactName; '
            'the plugin does not expose the carrier send result.',
          );
        } else if (status == SendStatus.DELIVERED) {
          debugPrint(
            'Carrier delivery report received for SMS to $contactName.',
          );
        }
      },
    );
  }
}
