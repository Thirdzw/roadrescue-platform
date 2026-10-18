import 'package:flutter/foundation.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/emergency_location_context.dart';
import 'emergency_event_logger.dart';
import 'demo_session.dart';

class EmergencyCallService {
  static Future<bool> callNumber({
    required String number,
    required String triggerType,
    required bool dryRun,
    required bool directCall,
    String? nearestCity,
  }) async {
    if (DemoSession.instance.isActive) {
      await EmergencyEventLogger.record(
        event: 'demo_call_simulated',
        triggerType: triggerType,
        nearestCity: nearestCity,
        numberDialed: number,
      );
      debugPrint('Demo mode: simulated call to $number; no call was placed.');
      return false;
    }
    await EmergencyEventLogger.record(
      event: dryRun ? 'dry_run_call' : 'call_attempt',
      triggerType: triggerType,
      nearestCity: nearestCity,
      numberDialed: number,
    );
    if (dryRun) {
      debugPrint('Dry run: would dial $number');
      return false;
    }

    if (directCall && defaultTargetPlatform == TargetPlatform.android) {
      final permission = await Permission.phone.request();
      if (permission.isGranted) {
        final result = await FlutterPhoneDirectCaller.callNumber(number);
        if (result == true) return true;
        debugPrint('Direct call failed; opening the dialer instead.');
      }
    }

    return launchUrl(
      Uri(scheme: 'tel', path: number),
      mode: LaunchMode.externalApplication,
    );
  }

  static String locationMessage(EmergencyLocationContext context) {
    final position = context.position;
    if (position == null) {
      throw StateError('A location fix is not available to share.');
    }
    return 'EMERGENCY: I have been in a vehicle accident. My location: '
        'https://maps.google.com/?q=${position.latitude},${position.longitude} '
        '(accuracy: ${position.accuracy.round()} m)';
  }

  static Future<bool> openSmsComposer({
    required EmergencyLocationContext context,
    required bool dryRun,
  }) async {
    final message = locationMessage(context);
    if (DemoSession.instance.isActive) dryRun = true;
    await EmergencyEventLogger.record(
      event: dryRun ? 'dry_run_message' : 'message_composer_opened',
      triggerType: 'share_location',
      nearestCity: context.nearbyCity?.name,
    );
    if (dryRun) {
      debugPrint('Dry run: would prefill SMS: $message');
      return false;
    }
    return launchUrl(
      Uri(scheme: 'sms', queryParameters: {'body': message}),
      mode: LaunchMode.externalApplication,
    );
  }
}
