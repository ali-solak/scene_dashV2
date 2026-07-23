library;

import '../../world/data/config.dart';

const int blasterBurstShots = 3;
const double blasterBurstInterval = 0.11;
const double blasterCooldown = 1.25;

const double blasterChargeThreshold = 0.25;

const double blasterMaxChargeDuration = 1.25;

const double chargedShotCooldown = 1.6;

const double projectileRadius = 0.18;
const double projectileSpeed = 22;
const double projectileLaunchUp = 3.2;
const double projectileLifetime = 0.8;

const double projectileKillY = -2;
const double projectileExitZ = -rampLength * 0.5 - 2;
const double projectileHitRadius = 1.05;
const double projectileKnockback = 13;
const double projectileLift = 4;

const double projectileBaseSpin = 9;

const double chargedProjectileMinScale = 1.6;
const double chargedProjectileMaxScale = 4.4;
const double chargedProjectileMinHitRadius = 1.8;
const double chargedProjectileMaxHitRadius = 3.4;

const int chargedProjectileMaxHits = 6;

const double chargedProjectileMaxKnockback = 30;
const double chargedProjectileMaxLift = 10;
const double chargedProjectileMaxSpin = 16;

const double minChargedCharge = 0.06;

const int impactBurstSeed = 23;
const int chargedImpactBurstSeed = 29;

const int impactBurstCount = 18;
const int chargedImpactBurstCount = 36;

const double impactBurstEntityLifetime = 0.7;

const int chargePlasmaSeed = 41;
const int chargePlasmaMaxParticles = 96;

const double chargePlasmaRateMin = 40;
const double chargePlasmaRateMax = 220;

const double chargePlasmaShellRadiusMin = 0.5;
const double chargePlasmaShellRadiusMax = 0.95;

const double reticleLaneHalfWidth = 1.7;

double chargedProjectileScale(double charge) {
  final t = charge.clamp(0.0, 1.0);
  return chargedProjectileMinScale +
      (chargedProjectileMaxScale - chargedProjectileMinScale) * t;
}

double projectileHitRadiusForCharge(double charge) {
  if (charge <= 0) return projectileHitRadius;
  final t = charge.clamp(0.0, 1.0);
  return chargedProjectileMinHitRadius +
      (chargedProjectileMaxHitRadius - chargedProjectileMinHitRadius) * t;
}

double projectileKnockbackForCharge(double charge) {
  if (charge <= 0) return projectileKnockback;
  final t = charge.clamp(0.0, 1.0);
  return projectileKnockback +
      (chargedProjectileMaxKnockback - projectileKnockback) * t;
}

double projectileLiftForCharge(double charge) {
  if (charge <= 0) return projectileLift;
  final t = charge.clamp(0.0, 1.0);
  return projectileLift + (chargedProjectileMaxLift - projectileLift) * t;
}

double projectileSpinForCharge(double charge) {
  if (charge <= 0) return projectileBaseSpin;
  final t = charge.clamp(0.0, 1.0);
  return projectileBaseSpin +
      (chargedProjectileMaxSpin - projectileBaseSpin) * t;
}
