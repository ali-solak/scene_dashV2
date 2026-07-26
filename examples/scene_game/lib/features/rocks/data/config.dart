library;

const double rockRadius = 0.7;

const double rockSpawnZ = -15;
const double rockSpawnY = 9;
const double rockSpawnHalfWidth = 6;

const double rockSpawnIntervalStart = 0.36;
const double rockSpawnIntervalMin = 0.15;
const double rockSpawnRampSeconds = 18;

const double flamingRockChanceStart = 0.18;
const double flamingRockChanceMax = 0.38;

const double flamingRockForwardVelocity = 15;
const double flamingRockSpinVelocity = 8;

const double rockKillY = -25;

const double rockHitReactionDuration = 0.34;

const int rockTrailSeed = 11;
const int rockTrailMaxParticles = 512;
const double rockTrailEmberRate = 70;

double stressRamp(double survived) {
  return (survived / rockSpawnRampSeconds).clamp(0, 1).toDouble();
}

double rockSpawnIntervalForSurvival(double survived) {
  final ramp = stressRamp(survived);
  return rockSpawnIntervalStart +
      (rockSpawnIntervalMin - rockSpawnIntervalStart) * ramp;
}

double flamingRockChanceForSurvival(double survived) {
  final ramp = stressRamp(survived);
  return flamingRockChanceStart +
      (flamingRockChanceMax - flamingRockChanceStart) * ramp;
}
