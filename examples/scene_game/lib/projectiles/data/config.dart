/// Projectile, blaster and lock-on reticle tuning for the scene game example.
library;

// --- Blaster ---

const int blasterBurstShots = 3;
const double blasterBurstInterval = 0.11;
const double blasterCooldown = 1.25;

/// Seconds of holding before a tap becomes a charge; releasing earlier fires
/// the normal burst.
const double blasterChargeThreshold = 0.25;

/// Seconds of holding that reaches full charge (clamped after that).
const double blasterMaxChargeDuration = 1.25;

/// Longer than [blasterCooldown] so a charged shot is a committed move.
const double chargedShotCooldown = 1.6;

// --- Projectiles ---

const double projectileRadius = 0.18;
const double projectileSpeed = 22;
const double projectileLaunchUp = 3.2;
const double projectileLifetime = 0.8;
const double projectileHitRadius = 1.05;
const double projectileKnockback = 13;
const double projectileLift = 4;

const double projectileBaseSpin = 9;

// --- Charged projectiles (min = lowest charge, max = full charge) ---

const double chargedProjectileMinScale = 1.6;
const double chargedProjectileMaxScale = 4.4;
const double chargedProjectileMinHitRadius = 1.8;
const double chargedProjectileMaxHitRadius = 3.4;

/// Rocks a charged shot can pierce before despawning.
const int chargedProjectileMaxHits = 6;

const double chargedProjectileMaxKnockback = 30;
const double chargedProjectileMaxLift = 10;
const double chargedProjectileMaxSpin = 16;

/// Floor for a charged shot's charge: keeps `0.0` meaning "burst pellet" and
/// any charged shot strictly above it.
const double minChargedCharge = 0.06;

// --- Lock-on reticle ---

/// A rock is a candidate target when its X is within this of the player's X.
const double reticleLaneHalfWidth = 1.7;

// --- Charge-derived scaling (charge <= 0 keeps the unscaled base value) ---

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
