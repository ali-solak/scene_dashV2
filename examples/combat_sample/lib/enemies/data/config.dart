part of '../enemies.dart';

const double enemyMaxHealth = 50;

const double giantScale = 1.7;
const double giantHealthFactor = 3.5;
const double giantPower = 2.2;

const double giantLaunchSpeed = 12.5;

const double giantTransformSeconds = 1.7;
const double transformClipSeconds = 1.0;

const int enemyPoints = 10;
const int giantPoints = 50;

const double enemyCapsuleRadius = 0.48;
const double enemyCapsuleHeight = 0.8;

const double healthBarHeight = 3;
const double healthBarWorldHeight = 0.2;

const double healthBarShakeSeconds = 0.3;
const double healthBarShakePop = 0.45;
const double healthBarShakeTilt = 0.22;

const double approachSpeed = 4.2;
const double circleSpeed = 2.3;

const double miredSpeedFactor = 0.32;

const double circleRadius = 4.4;
const double circleWobbleAmplitude = 0.7;
const double circleWobbleRate = 0.7;

const double engageRange = 6.2;

const double tokenCloseSpeed = 3.6;

const double brawlerAttackRange = 2.6;

const double telegraphSeconds = 0.6;
const double swingSeconds = 0.18;
const double recoverSeconds = 0.75;

const double brawlStaggerSeconds = 0.8;

const double brawlerDamage = 15;

const double aggroCooldownSeconds = 1.2;

const double dissolveSeconds = 1.8;

const double dissolveDelaySeconds = 0.7;

const double deathSinkDepth = 2.2;

final Vector3 corpseHalfExtents = Vector3(0.45, 1.2, 0.35);

const double corpseHopVelocity = 3.4;
const double corpseTumbleFactor = 1.6;

const double corpseLinearDamping = 2.4;
const double corpseAngularDamping = 1.4;

const double corpseSettleSeconds = 1.4;

const double corpseLaunchFactor = 0.45;

const double brawlerLocomotionFadeSeconds = 0.001;
const double brawlerOneShotFadeSeconds = 0.001;

const double brawlerWalkStrideSpeed = 2.3;
const double brawlerRunStrideSpeed = 5.2;
const double brawlerStrafeStrideSpeed = 3.2;

const double brawlerRunBlendSpeed = 3.4;

const double chopClipSeconds = 1.63;
const double hitBClipSeconds = 0.87;
const double deathBClipSeconds = 2.63;

const double risingSeconds = 2.30;
const double awakenClipSeconds = 2.30;

const double tauntSeconds = 1.03;
const double tauntClipSeconds = 1.033;
const double tauntIntervalSeconds = 7.0;

const double brawlerFlinchSeconds = 0.32;

const double proneSettleRate = 2.6;

final Vector4 telegraphEmissive = Vector4(1.0, 0.42, 0.12, 1);
