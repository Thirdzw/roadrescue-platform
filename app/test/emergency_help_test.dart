import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadrescue/models/crash_evidence_score.dart';
import 'package:roadrescue/models/emergency_data.dart';
import 'package:roadrescue/services/emergency_countdown_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EmergencyData data;

  setUpAll(() async {
    final source = await rootBundle.loadString('assets/emergency_data.json');
    data = EmergencyData.fromJson(jsonDecode(source) as Map<String, dynamic>);
  });

  group('nearestCity', () {
    test('matches Borrowdale with Harare', () {
      final result = nearestCity(data.cities, -17.7600, 31.0900);
      expect(result.city?.id, 'harare');
      expect(result.isWithinRange, isTrue);
    });

    test('matches Bulawayo CBD', () {
      final result = nearestCity(data.cities, -20.1500, 28.5800);
      expect(result.city?.id, 'bulawayo');
      expect(result.isWithinRange, isTrue);
    });

    test('matches Victoria Falls town', () {
      final result = nearestCity(data.cities, -17.9300, 25.8300);
      expect(result.city?.id, 'victoria_falls');
      expect(result.isWithinRange, isTrue);
    });

    test('uses national fallback beyond 150 km', () {
      final result = nearestCity(data.cities, -22.2160, 30.0000);
      expect(result.isWithinRange, isFalse);
      expect(result.distanceKm, greaterThan(150));
    });
  });

  group('ZimbabwePhoneNumberNormalizer', () {
    test('normalizes Zimbabwe local and international formats', () {
      expect(
          ZimbabwePhoneNumberNormalizer.normalize('04-797 479'), '+2634797479');
      expect(ZimbabwePhoneNumberNormalizer.normalize('(+263 4) 748 836'),
          '+2634748836');
      expect(ZimbabwePhoneNumberNormalizer.normalize('0772 141 610'),
          '+263772141610');
      expect(ZimbabwePhoneNumberNormalizer.normalize('(263 773) 300 800'),
          '+263773300800');
      expect(ZimbabwePhoneNumberNormalizer.normalize('999'), '999');
    });

    test('leaves ambiguous numbers visible but non-dialable', () {
      expect(ZimbabwePhoneNumberNormalizer.normalize('772830979'), isNull);
      expect(ZimbabwePhoneNumberNormalizer.normalize('133 000'), isNull);
      expect(ZimbabwePhoneNumberNormalizer.normalize('not a number'), isNull);
    });

    test('every bundled number is either normalizable or safely disabled', () {
      for (final contact in [
        ...data.national,
        ...data.roadAssistance,
        for (final city in data.cities) ...city.ambulance,
        for (final city in data.cities) ...city.police,
        for (final city in data.cities) ...city.fire,
        for (final city in data.cities) ...city.hospitals,
      ]) {
        for (final phone in contact.phones) {
          final normalized = ZimbabwePhoneNumberNormalizer.normalize(phone);
          if (normalized != null) {
            expect(
                RegExp(r'^\+263[0-9]+$|^(999|995|993|112|114)$')
                    .hasMatch(normalized),
                isTrue,
                reason: phone);
          }
        }
      }
    });
  });

  group('EmergencyCountdownController', () {
    test('cancelling before zero never calls', () async {
      var calls = 0;
      final controller = EmergencyCountdownController(
        countdownSeconds: 100,
        dryRun: false,
        tickInterval: const Duration(milliseconds: 5),
        onCall: () async => calls++,
      )..start();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      controller.cancel();
      await controller.completed;
      expect(calls, 0);
      controller.dispose();
    });

    test('reaching zero calls exactly once', () async {
      var calls = 0;
      final controller = EmergencyCountdownController(
        countdownSeconds: 2,
        dryRun: false,
        tickInterval: const Duration(milliseconds: 2),
        onCall: () async => calls++,
      )..start();
      await controller.completed.timeout(const Duration(seconds: 1));
      expect(calls, 1);
      controller.dispose();
    });

    test('dry-run never calls and invokes preview once', () async {
      var calls = 0;
      var previews = 0;
      final controller = EmergencyCountdownController(
        countdownSeconds: 1,
        dryRun: true,
        tickInterval: const Duration(milliseconds: 2),
        onCall: () async => calls++,
        onDryRun: () => previews++,
      )..start();
      await controller.completed.timeout(const Duration(seconds: 1));
      expect(calls, 0);
      expect(previews, 1);
      controller.dispose();
    });
  });

  group('CrashEvidenceScore', () {
    test('uses phone impact, speed collapse, stillness, and optional cues', () {
      const requiredEvidence = CrashEvidenceScore(
        impactSpike: true,
        speedCollapse: true,
        stillness: true,
      );
      const allEvidence = CrashEvidenceScore(
        impactSpike: true,
        speedCollapse: true,
        stillness: true,
        gyroscopeSpike: true,
        barometerChange: true,
        loudSound: true,
      );

      expect(requiredEvidence.total, 6);
      expect(allEvidence.total, 9);
      expect(allEvidence.toMap()['speedCollapse'], isTrue);
    });

    test('score reports detected evidence without acting as a gate', () {
      expect(
        const CrashEvidenceScore(
          impactSpike: true,
          speedCollapse: true,
          stillness: true,
        ).total,
        6,
      );
    });
  });
}
