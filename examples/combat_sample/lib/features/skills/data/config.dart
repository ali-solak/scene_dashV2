part of '../skills.dart';

const int maxSkillLevel = 5;

const double skillPowerPerLevel = 0.4;

const double fireGushRange = 8.5;
const double fireGushHalfArc = 0.55;
const double fireGushDamage = 26;
const double fireGushKnockback = 2.5;

const double fireGushRecoil = 5.5;
const double fireGushCooldownSeconds = 7;
const int fireGushCost = 30;
const int fireGushCostStep = 22;

const double fireGushMuzzleHeight = 1.6;

const double burnSeconds = 4.5;
const double burnTickSeconds = 0.5;
const double burnTickDamage = 5;

const double lavaPitRadius = 3.4;
const double lavaPitDistance = 5.5;
const double lavaPitSeconds = 9;
const double lavaTickSeconds = 0.4;
const double lavaTickDamage = 7;
const double lavaPitCooldownSeconds = 16;
const int lavaPitCost = 60;
const int lavaPitCostStep = 40;

const double lavaPitLift = 0.03;

const double lavaBurnSeconds = 2.2;

const double lavaBurnTickDamage = 3;

const double lavaMireLinger = 0.35;

const double lavaPitOpenSeconds = 0.5;
const double lavaPitCoolSeconds = 1.5;

const double windBlastRadius = 11;
const double windBlastDamage = 12;
const double windBlastSpeed = 10;
const double windBlastLift = 12.5;
const double windBlastCooldownSeconds = 11;
const int windBlastCost = 45;
const int windBlastCostStep = 30;

const int shieldBaseCharges = 3;
const int shieldChargesPerLevel = 1;

const double shieldCooldownSeconds = 18;
const int shieldCost = 40;
const int shieldCostStep = 28;

const double shieldRadius = 1.5;
const double shieldHeight = 1.3;

const double shieldFlashSeconds = 0.22;

final Quaternion shieldMountRotation = Quaternion.axisAngle(
  Vector3(0, 1, 1).normalized(),
  math.pi,
);

const int shieldMaxCharges =
    shieldBaseCharges + shieldChargesPerLevel * (maxSkillLevel - 1);

int shieldChargesFor(int level) =>
    level <= 0 ? 0 : shieldBaseCharges + shieldChargesPerLevel * (level - 1);

const double vitalityHealthPerLevel = 30;
const int vitalityBaseCost = 25;
const int vitalityCostStep = 20;
const int maxVitalityLevel = 8;

int vitalityCost(int level) => vitalityBaseCost + vitalityCostStep * level;
