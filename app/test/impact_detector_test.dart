import 'package:flutter_test/flutter_test.dart';
import 'package:roadrescue/logic/crash_fusion.dart';

void main() {
  group('CrashFusion', () {
    final start = DateTime.utc(2026, 10, 15);

    test('requires an impact above 4g and prior speed of at least 25 mph', () {
      final fusion = CrashFusion();
      fusion.onSpeed(24.9, start);
      expect(fusion.onAccel(4, start.add(const Duration(seconds: 1))), isFalse);
      expect(
        fusion.onAccel(4.01, start.add(const Duration(seconds: 2))),
        isFalse,
      );

      fusion.onSpeed(25, start.add(const Duration(seconds: 3)));
      expect(
        fusion.onAccel(4.01, start.add(const Duration(seconds: 4))),
        isTrue,
      );
    });

    test('rejects free-fall in the preceding 600ms window', () {
      final fusion = CrashFusion();
      final impactAt = start.add(const Duration(seconds: 2));
      fusion.onSpeed(40, start);
      fusion.onAccel(0.2, impactAt.subtract(const Duration(milliseconds: 599)));
      expect(fusion.onAccel(4.2, impactAt), isFalse);
    });

    test('does not reject free-fall exactly 600ms before a spike', () {
      final fusion = CrashFusion();
      final impactAt = start.add(const Duration(seconds: 2));
      fusion.onSpeed(40, start);
      fusion.onAccel(0.2, impactAt.subtract(const Duration(milliseconds: 600)));
      expect(fusion.onAccel(4.2, impactAt), isTrue);
    });

    test('tracks the peak only during the first 500ms', () {
      final fusion = _candidate(
        at: start,
        peakG: 4.2,
        speedNowMph: 20,
      );
      fusion.onAccel(7, start.add(const Duration(milliseconds: 400)));
      fusion.onAccel(12, start.add(const Duration(milliseconds: 600)));
      expect(
          fusion.assess(at: start.add(const Duration(seconds: 3)))!.peakG, 7);
    });

    test('speed collapse and stillness contribute 3 and 1 points', () {
      final fusion = _candidate(
        at: start,
        speedNowMph: 3,
        speedBeforeMph: 30,
        still: true,
      );
      final assessment =
          fusion.assess(at: start.add(const Duration(seconds: 3)))!;

      expect(assessment.score, 6);
      expect(assessment.action, CrashAction.normalCountdown);
      expect(assessment.severity, Severity.moderate);
      expect(assessment.countdownSeconds, 30);
    });

    test('gyro adds a point and upgrades minor severity to moderate', () {
      final fusion = _candidate(at: start, speedNowMph: 30);
      fusion.onGyro(6.1, start.add(const Duration(milliseconds: 200)));
      final assessment =
          fusion.assess(at: start.add(const Duration(seconds: 3)))!;

      expect(assessment.score, 3);
      expect(assessment.action, CrashAction.silentCheck);
      expect(assessment.severity, Severity.moderate);
    });

    test('severe crashes with at least five points use the short countdown',
        () {
      final fusion = _candidate(
        at: start,
        peakG: 8.1,
        speedBeforeMph: 50,
        speedNowMph: 0,
      );
      final assessment =
          fusion.assess(at: start.add(const Duration(seconds: 3)))!;

      expect(assessment.score, 5);
      expect(assessment.severity, Severity.severe);
      expect(assessment.action, CrashAction.shortCountdown);
      expect(assessment.countdownSeconds, 10);
    });

    test('score seven uses the short countdown', () {
      final fusion = _candidate(
        at: start,
        speedBeforeMph: 30,
        speedNowMph: 3,
        still: true,
      );
      fusion.onGyro(6.1, start.add(const Duration(milliseconds: 200)));
      final assessment =
          fusion.assess(at: start.add(const Duration(seconds: 3)))!;

      expect(assessment.score, 7);
      expect(assessment.action, CrashAction.shortCountdown);
      expect(
        CrashAssessment.fromMap(assessment.toMap()).evidence,
        assessment.evidence,
      );
    });

    test('impact alone is ignored and does not imply a crash', () {
      final fusion = _candidate(at: start, speedNowMph: 30);
      final assessment =
          fusion.assess(at: start.add(const Duration(seconds: 3)))!;

      expect(assessment.score, 2);
      expect(assessment.action, CrashAction.ignore);
    });

    test('pressure and sound cues each add one optional point', () {
      final fusion = _candidate(at: start, speedNowMph: 30);
      fusion.onPressureSpike(start.add(const Duration(milliseconds: 100)));
      fusion.onLoudSound(start.add(const Duration(milliseconds: 150)));
      final assessment =
          fusion.assess(at: start.add(const Duration(seconds: 3)))!;

      expect(assessment.score, 4);
      expect(assessment.action, CrashAction.silentCheck);
      expect(assessment.evidenceScore.barometerChange, isTrue);
      expect(assessment.evidenceScore.loudSound, isTrue);
    });

    test('stillness requires low variance over enough recent samples', () {
      final fusion = _candidate(
        at: start,
        speedNowMph: 3,
        still: false,
      );
      final assessment =
          fusion.assess(at: start.add(const Duration(seconds: 3)))!;

      expect(assessment.evidence.contains(Evidence.still), isFalse);
      expect(assessment.score, 5);
    });
  });
}

CrashFusion _candidate({
  required DateTime at,
  double peakG = 4.2,
  double speedBeforeMph = 30,
  double speedNowMph = 30,
  bool still = false,
}) {
  final fusion = CrashFusion();
  fusion.onSpeed(speedBeforeMph, at.subtract(const Duration(seconds: 1)));
  for (var sample = 0; sample < 100; sample++) {
    fusion.onAccel(
      1,
      at.subtract(Duration(milliseconds: 2000 - sample * 20)),
    );
  }
  expect(fusion.onAccel(peakG, at), isTrue);
  fusion.onSpeed(speedNowMph, at.add(const Duration(seconds: 1)));
  for (var sample = 0; sample < 100; sample++) {
    fusion.onAccel(
      still ? 1 + (sample.isEven ? 0.01 : -0.01) : (sample.isEven ? 0.5 : 1.5),
      at.add(Duration(milliseconds: 1000 + sample * 20)),
    );
  }
  return fusion;
}
