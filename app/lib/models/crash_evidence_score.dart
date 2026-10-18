import 'emergency_config.dart';

class CrashEvidenceScore {
  final bool impactSpike;
  final bool speedCollapse;
  final bool stillness;
  final bool gyroscopeSpike;
  final bool barometerChange;
  final bool loudSound;

  const CrashEvidenceScore({
    this.impactSpike = false,
    this.speedCollapse = false,
    this.stillness = false,
    this.gyroscopeSpike = false,
    this.barometerChange = false,
    this.loudSound = false,
  });

  int get total =>
      (impactSpike ? crashImpactEvidencePoints : 0) +
      (speedCollapse ? crashSpeedCollapseEvidencePoints : 0) +
      (stillness ? crashStillnessEvidencePoints : 0) +
      (gyroscopeSpike ? crashGyroscopeEvidencePoints : 0) +
      (barometerChange ? crashBarometerEvidencePoints : 0) +
      (loudSound ? crashSoundEvidencePoints : 0);

  Map<String, Object> toMap() => {
        'impactSpike': impactSpike,
        'speedCollapse': speedCollapse,
        'stillness': stillness,
        'gyroscopeSpike': gyroscopeSpike,
        'barometerChange': barometerChange,
        'loudSound': loudSound,
        'total': total,
      };
}
