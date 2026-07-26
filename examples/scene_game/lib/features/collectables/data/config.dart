library;

import '../../player/data/config.dart';
import '../../world/data/config.dart';

const double collectableRadius = 0.5;

const double shieldPickupSpawnZ = -14;
const double shieldPickupSpawnY = 7.5;
const double shieldPickupSpawnHalfWidth = 5;

const double shieldPickupInterval = 9;

const double collectableKillY = -25;
const double collectablePassZ = rampLength * 0.5 + 3;

final double shieldCollectDistanceSq = _square(
  playerCollisionRadius + collectableRadius + 0.5,
);

double _square(double value) => value * value;

const double shieldDuration = 6;

const double shieldWarningWindow = 1.5;

const double shieldDeflectTimeCost = 0.4;

const double shieldDeflectOutward = 16;
const double shieldDeflectUp = 12;
const double shieldDeflectSpin = 10;

const int deflectBurstSeed = 31;
const int deflectBurstCount = 18;
const double deflectBurstEntityLifetime = 0.6;
