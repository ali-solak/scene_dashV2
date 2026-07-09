/// Rock tuning and difficulty scaling for the scene game example.
library;

const double rockRadius = 0.7;

/// Spawn band at the high end of the ramp.
const double rockSpawnZ = -15;
const double rockSpawnY = 9;
const double rockSpawnHalfWidth = 6;

/// Spawn cadence ramps from start toward min over [rockSpawnRampSeconds], so
/// the game stays playable before becoming a small physics stress test.
const double rockSpawnIntervalStart = 0.36;
const double rockSpawnIntervalMin = 0.15;
const double rockSpawnRampSeconds = 18;

/// Chance of the faster flaming variant, ramping up with the spawn cadence.
const double flamingRockChanceStart = 0.18;
const double flamingRockChanceMax = 0.38;

const double flamingRockForwardVelocity = 15;
const double flamingRockSpinVelocity = 8;

/// Rocks that fall below this Y are despawned.
const double rockKillY = -25;

const double rockHitReactionDuration = 0.34;

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
