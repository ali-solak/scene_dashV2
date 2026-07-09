/// Shield-pickup and shield tuning for the scene game example.
library;

import '../../player/data/config.dart';
import '../../world/data/config.dart';

// --- Shield pickups ---

const double collectableRadius = 0.5;

/// Spawn band at the high (-Z) end of the ramp so pickups roll down toward the
/// player like rocks do.
const double shieldPickupSpawnZ = -14;
const double shieldPickupSpawnY = 7.5;
const double shieldPickupSpawnHalfWidth = 5;

const double shieldPickupInterval = 9;

/// Pickups despawn once they fall below this Y or roll past this Z.
const double collectableKillY = -25;
final double collectablePassZ = rampLength * 0.5 + 3;

final double shieldCollectDistanceSq = _square(
  playerCollisionRadius + collectableRadius + 0.5,
);

double _square(double value) => value * value;

// --- Shield ---

const double shieldDuration = 6;

/// Final seconds during which the shield visibly warns of expiry.
const double shieldWarningWindow = 1.5;

/// Seconds of shield time consumed by deflecting a single rock.
const double shieldDeflectTimeCost = 0.4;

/// Velocities applied to a rock the shield deflects.
const double shieldDeflectOutward = 16;
const double shieldDeflectUp = 12;
const double shieldDeflectSpin = 10;
