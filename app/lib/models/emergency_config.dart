// City coordinates are approximate and must be verified before release.
const emergencyCityRadiusKm = 150.0;
const emergencyCountdownSeconds = 10;

// User-accelerometer magnitude thresholds are in m/s^2 (gravity excluded).
// Tune against recorded phone data before enabling automatic detection by default.
const accelerometerCrashThresholdMps2 = 32.0;
const accelerometerHardImpactMps2 = 48.0;
const accelerometerImpactWindow = Duration(milliseconds: 500);
const accelerometerSamplesRequired = 3;
const crashDetectionCooldown = Duration(seconds: 45);

// Crash-detection thresholds are normalized to g and mph for field tuning.
const crashSpeedThresholdMph = 25.0;
const crashArmedGracePeriod = Duration(seconds: 30);
const crashGpsSampleFreshness = Duration(seconds: 5);
const crashImpactThresholdG = 4.0;
const crashFreeFallThresholdG = 0.4;
const crashFreeFallLookback = Duration(milliseconds: 600);
const crashConfirmationDelay = Duration(seconds: 3);
const crashStoppedSpeedMph = 5.0;
const crashStillnessVarianceThreshold = 0.01;
const crashStillnessWindow = Duration(seconds: 2);
const crashStillnessMinimumSamples = 50;
const crashSensorSamplingPeriod = Duration(milliseconds: 20);
const crashGyroscopeSpikeRadPerSecond = 6.0;
const crashBarometerPressureChangeHpa = 0.5;
const crashSoundRmsThreshold = 0.15;
const crashSupplementalEvidenceWindow = Duration(seconds: 3);
const crashImpactEvidencePoints = 2;
const crashSpeedCollapseEvidencePoints = 3;
const crashStillnessEvidencePoints = 1;
const crashGyroscopeEvidencePoints = 1;
const crashBarometerEvidencePoints = 1;
const crashSoundEvidencePoints = 1;
const crashMicrophoneSampleRate = 16000;
const gravityMetersPerSecondSquared = 9.81;
const metersPerSecondToMilesPerHour = 2.2369362921;
const crashResponseCountdownSeconds = 30;
const crashLastKnownPositionMaxAge = Duration(minutes: 2);
const crashVerificationAttempts = 4;
