import 'dart:collection';

import '../models/crash_evidence_score.dart';
import '../models/emergency_config.dart';

enum Evidence {
  impact,
  speedCollapse,
  still,
  gyroSpike,
  pressureSpike,
  loudSound,
}

enum Severity { minor, moderate, severe }

enum CrashAction { ignore, silentCheck, normalCountdown, shortCountdown }

class CrashFusionTuning {
  static const impactG = crashImpactThresholdG;
  static const freeFallG = crashFreeFallThresholdG;
  static const freeFallWindow = crashFreeFallLookback;
  static const armMph = crashSpeedThresholdMph;
  static const stoppedMph = crashStoppedSpeedMph;
  static const preImpactSpeedWindow = Duration(seconds: 10);
  static const evidenceWindow = Duration(seconds: 15);
  static const peakWindow = Duration(milliseconds: 500);
  static const gyroSpikeRadPerSecond = crashGyroscopeSpikeRadPerSecond;
  static const gyroWindow = Duration(seconds: 2);
  static const stillVariance = crashStillnessVarianceThreshold;
  static const moderateG = 5.5;
  static const severeG = 8.0;
  static const moderateLossMph = 25.0;
  static const severeLossMph = 40.0;
  static const shortCountdownSeconds = 10;
  static const normalCountdownSeconds = crashResponseCountdownSeconds;
}

class CrashAssessment {
  const CrashAssessment({
    required this.action,
    required this.severity,
    required this.score,
    required this.peakG,
    required this.speedBeforeMph,
    required this.speedNowMph,
    required this.evidence,
  });

  final CrashAction action;
  final Severity severity;
  final int score;
  final double peakG;
  final double speedBeforeMph;
  final double speedNowMph;
  final Set<Evidence> evidence;

  int get countdownSeconds => action == CrashAction.shortCountdown
      ? CrashFusionTuning.shortCountdownSeconds
      : CrashFusionTuning.normalCountdownSeconds;

  CrashEvidenceScore get evidenceScore => CrashEvidenceScore(
        impactSpike: evidence.contains(Evidence.impact),
        speedCollapse: evidence.contains(Evidence.speedCollapse),
        stillness: evidence.contains(Evidence.still),
        gyroscopeSpike: evidence.contains(Evidence.gyroSpike),
        barometerChange: evidence.contains(Evidence.pressureSpike),
        loudSound: evidence.contains(Evidence.loudSound),
      );

  String summary() => '${severity.name}: ${speedBeforeMph.round()} to '
      '${speedNowMph.round()} mph, peak ${peakG.toStringAsFixed(1)}g';

  Map<String, Object> toMap() => {
        'action': action.name,
        'severity': severity.name,
        'score': score,
        'peakG': peakG,
        'speedBeforeMph': speedBeforeMph,
        'speedNowMph': speedNowMph,
        'evidence': evidence.map((item) => item.name).toList(growable: false),
      };

  factory CrashAssessment.fromMap(Map<String, dynamic> map) {
    final action = _enumValue(CrashAction.values, map['action']);
    final severity = _enumValue(Severity.values, map['severity']);
    final evidenceNames = map['evidence'];
    if (evidenceNames is! List) {
      throw const FormatException('Crash evidence is missing.');
    }
    final evidence = <Evidence>{};
    for (final name in evidenceNames) {
      evidence.add(_enumValue(Evidence.values, name));
    }
    final score = (map['score'] as num?)?.toInt();
    final peakG = (map['peakG'] as num?)?.toDouble();
    final speedBeforeMph = (map['speedBeforeMph'] as num?)?.toDouble();
    final speedNowMph = (map['speedNowMph'] as num?)?.toDouble();
    if (score == null ||
        peakG == null ||
        speedBeforeMph == null ||
        speedNowMph == null ||
        !peakG.isFinite ||
        !speedBeforeMph.isFinite ||
        !speedNowMph.isFinite) {
      throw const FormatException('Crash assessment values are invalid.');
    }
    final computedScore =
        evidence.fold<int>(0, (total, item) => total + CrashFusion.weights[item]!);
    final expectedAction = computedScore >= 7 ||
            (severity == Severity.severe && computedScore >= 5)
        ? CrashAction.shortCountdown
        : computedScore >= 5
            ? CrashAction.normalCountdown
            : computedScore >= 3
                ? CrashAction.silentCheck
                : CrashAction.ignore;
    if (!evidence.contains(Evidence.impact) ||
        score != computedScore ||
        action != expectedAction ||
        action == CrashAction.silentCheck ||
        action == CrashAction.ignore) {
      throw const FormatException('Persisted crash action is inconsistent.');
    }
    return CrashAssessment(
      action: action,
      severity: severity,
      score: score,
      peakG: peakG,
      speedBeforeMph: speedBeforeMph,
      speedNowMph: speedNowMph,
      evidence: evidence,
    );
  }

  static T _enumValue<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) {
      throw const FormatException('Crash assessment enum is invalid.');
    }
    return values.firstWhere(
      (value) => value.name == name,
      orElse: () => throw const FormatException('Unknown crash assessment enum.'),
    );
  }
}

class _SpeedSample {
  const _SpeedSample(this.timestamp, this.mph);

  final DateTime timestamp;
  final double mph;
}

class _AccelerationSample {
  const _AccelerationSample(this.timestamp, this.g);

  final DateTime timestamp;
  final double g;
}

class CrashFusion {
  static const weights = <Evidence, int>{
    Evidence.impact: crashImpactEvidencePoints,
    Evidence.speedCollapse: crashSpeedCollapseEvidencePoints,
    Evidence.still: crashStillnessEvidencePoints,
    Evidence.gyroSpike: crashGyroscopeEvidencePoints,
    Evidence.pressureSpike: crashBarometerEvidencePoints,
    Evidence.loudSound: crashSoundEvidencePoints,
  };

  final Queue<_SpeedSample> _speeds = Queue<_SpeedSample>();
  final Queue<_AccelerationSample> _recentG = Queue<_AccelerationSample>();

  DateTime? _lastFreeFall;
  DateTime? _impactAt;
  DateTime? _gyroAt;
  DateTime? _pressureAt;
  DateTime? _soundAt;
  double _peakG = 0;
  double _speedBefore = 0;
  double _speedNow = 0;

  void onSpeed(double mph, [DateTime? at]) {
    if (!mph.isFinite || mph < 0) return;
    final timestamp = at ?? DateTime.now();
    _speedNow = mph;
    _speeds.addLast(_SpeedSample(timestamp, mph));
    while (_speeds.isNotEmpty &&
        timestamp.difference(_speeds.first.timestamp) >
            const Duration(seconds: 30)) {
      _speeds.removeFirst();
    }
  }

  /// Adds an accelerometer magnitude in g. True means a new impact candidate.
  bool onAccel(double g, [DateTime? at]) {
    if (!g.isFinite || g < 0) return false;
    final now = at ?? DateTime.now();
    _recentG.addLast(_AccelerationSample(now, g));
    while (_recentG.length > crashStillnessMinimumSamples * 2) {
      _recentG.removeFirst();
    }
    if (g < CrashFusionTuning.freeFallG) _lastFreeFall = now;

    final impactAt = _impactAt;
    if (impactAt != null &&
        !now.isBefore(impactAt) &&
        now.difference(impactAt) < CrashFusionTuning.evidenceWindow) {
      if (now.difference(impactAt) < CrashFusionTuning.peakWindow &&
          g > _peakG) {
        _peakG = g;
      }
      return false;
    }
    if (g <= CrashFusionTuning.impactG) return false;

    final lastFreeFall = _lastFreeFall;
    final falling = lastFreeFall != null &&
        !now.isBefore(lastFreeFall) &&
        now.difference(lastFreeFall) < CrashFusionTuning.freeFallWindow;
    if (falling) return false;

    final speedBefore = _maxSpeedBefore(now);
    if (speedBefore < CrashFusionTuning.armMph) return false;

    _impactAt = now;
    _peakG = g;
    _speedBefore = speedBefore;
    return true;
  }

  void onGyro(double radPerSecond, [DateTime? at]) {
    if (radPerSecond.isFinite &&
        radPerSecond > CrashFusionTuning.gyroSpikeRadPerSecond) {
      _gyroAt = at ?? DateTime.now();
    }
  }

  void onPressureSpike([DateTime? at]) => _pressureAt = at ?? DateTime.now();

  void onLoudSound([DateTime? at]) => _soundAt = at ?? DateTime.now();

  CrashAssessment? assess({DateTime? at}) {
    final impactAt = _impactAt;
    if (impactAt == null) return null;
    final now = at ?? DateTime.now();
    final evidence = <Evidence>{Evidence.impact};
    if (_speedNow < CrashFusionTuning.stoppedMph) {
      evidence.add(Evidence.speedCollapse);
    }
    if (_isStill(now)) evidence.add(Evidence.still);
    if (_near(_gyroAt, impactAt)) evidence.add(Evidence.gyroSpike);
    if (_near(_pressureAt, impactAt)) evidence.add(Evidence.pressureSpike);
    if (_near(_soundAt, impactAt)) evidence.add(Evidence.loudSound);

    final score =
        evidence.fold<int>(0, (total, item) => total + weights[item]!);
    final speedLoss = _speedBefore - _speedNow;
    var severity = Severity.minor;
    if (_peakG >= CrashFusionTuning.severeG ||
        speedLoss >= CrashFusionTuning.severeLossMph) {
      severity = Severity.severe;
    } else if (_peakG >= CrashFusionTuning.moderateG ||
        speedLoss >= CrashFusionTuning.moderateLossMph) {
      severity = Severity.moderate;
    }
    if (evidence.contains(Evidence.gyroSpike) && severity == Severity.minor) {
      severity = Severity.moderate;
    }

    final action = switch (score) {
      >= 7 => CrashAction.shortCountdown,
      >= 5 when severity == Severity.severe => CrashAction.shortCountdown,
      >= 5 => CrashAction.normalCountdown,
      >= 3 => CrashAction.silentCheck,
      _ => CrashAction.ignore,
    };

    return CrashAssessment(
      action: action,
      severity: severity,
      score: score,
      peakG: _peakG,
      speedBeforeMph: _speedBefore,
      speedNowMph: _speedNow,
      evidence: evidence,
    );
  }

  void reset() {
    _impactAt = null;
    _peakG = 0;
    _speedBefore = 0;
    _gyroAt = null;
    _pressureAt = null;
    _soundAt = null;
  }

  double _maxSpeedBefore(DateTime timestamp) {
    var maxSpeed = 0.0;
    for (final sample in _speeds) {
      final elapsed = timestamp.difference(sample.timestamp);
      if (!elapsed.isNegative &&
          elapsed <= CrashFusionTuning.preImpactSpeedWindow &&
          sample.mph > maxSpeed) {
        maxSpeed = sample.mph;
      }
    }
    return maxSpeed;
  }

  bool _isStill(DateTime now) {
    final samples = _recentG
        .where(
          (sample) =>
              !sample.timestamp.isAfter(now) &&
              now.difference(sample.timestamp) <= crashStillnessWindow,
        )
        .map((sample) => sample.g)
        .toList(growable: false);
    if (samples.length < crashStillnessMinimumSamples) return false;
    final mean = samples.reduce((a, b) => a + b) / samples.length;
    final variance = samples
            .map((value) => (value - mean) * (value - mean))
            .reduce((a, b) => a + b) /
        samples.length;
    return variance < CrashFusionTuning.stillVariance;
  }

  bool _near(DateTime? timestamp, DateTime impactAt) =>
      timestamp != null &&
      timestamp.difference(impactAt).abs() <= CrashFusionTuning.gyroWindow;
}
