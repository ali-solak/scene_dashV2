part of '../enemies.dart';

// ── Stats & scoring ─────────────────────────────────────────────────────

const double enemyMaxHealth = 50;
const double brawlerDamage = 15;

const int enemyPoints = 10;
const int giantPoints = 50;

// ── The giant ───────────────────────────────────────────────────────────

const double giantScale = 1.7;
const double giantHealthFactor = 3.5;
const double giantPower = 2.2;
const double giantLaunchSpeed = 12.5;

const double giantTransformSeconds = 1.7;
const double transformClipSeconds = 1.0;

// ── Graybox capsule fallback ────────────────────────────────────────────

const double enemyCapsuleRadius = 0.48;
const double enemyCapsuleHeight = 0.8;

// ── Health bar ──────────────────────────────────────────────────────────

const double healthBarHeight = 3;
const double healthBarWorldHeight = 0.2;

const double healthBarShakeSeconds = 0.3;
const double healthBarShakePop = 0.45;
const double healthBarShakeTilt = 0.22;

// ── Locomotion: approach & circle ───────────────────────────────────────

const double approachSpeed = 4.2;
const double circleSpeed = 2.3;
const double tokenCloseSpeed = 3.6;

/// Ground-speed factor while bogged down in a lava pit.
const double miredSpeedFactor = 0.32;

const double circleRadius = 4.4;
const double circleWobbleAmplitude = 0.7;
const double circleWobbleRate = 0.7;

const double engageRange = 6.2;
const double brawlerAttackRange = 2.6;

// ── The attack arc & stagger ────────────────────────────────────────────

const double telegraphSeconds = 0.6;
const double swingSeconds = 0.18;
const double recoverSeconds = 0.75;

const double brawlStaggerSeconds = 0.8;

/// The heavy pattern: some approaches open a two-chop combo. The opener
/// winds up slower than an ordinary chop (the tell that says commit or
/// get clear), the two are linked by a short recover, and the follow-up
/// lands fast. Giants pull it more often.
const double comboChance = 0.35;
const double giantComboChance = 0.6;
const double comboOpenerSeconds = 0.95;
const double comboLinkSeconds = 0.22;
const double comboFollowSeconds = 0.28;

const double aggroCooldownSeconds = 1.2;

// ── The sidestep ────────────────────────────────────────────────────────

/// Reading the player's windup, a circling barbarian sometimes rolls
/// clear instead of standing in the arc. Reactive rather than random, so
/// it reads as the pack respecting your weapon; the cooldown keeps it an
/// occasional beat rather than a wall of evasion.
const double dodgeChance = 0.45;
const double dodgeCooldownSeconds = 3.5;

/// The window IS the clip, so the roll animates the whole move instead
/// of finishing early and leaving the body sliding.
const double dodgeClipSeconds = 0.4;
const double dodgeSeconds = dodgeClipSeconds;

/// Mostly backward, because the player's strike arc is ~195° wide: a
/// pure sidestep stays inside it, so only opening the distance past
/// `playerReach` actually beats a swing. The side component is what
/// keeps it from reading as a stiff hop straight back.
const double dodgeBackWeight = 0.85;
const double dodgeSideWeight = 0.55;

/// Fast enough to clear the reach inside a light attack's 0.18 s windup,
/// but the window is short so the body still covers only ~2.6 m and does
/// not outrun its own animation.
const double dodgeSpeed = 6.5;

/// Only a swing that could plausibly land draws a dodge: inside this
/// reach AND inside the arc the player is actually facing. A shade wider
/// than the real strike arc, so they respect near-misses too.
const double dodgeThreatRange = 4.2;
const double dodgeThreatHalfArc = 1.9;

// ── Death: dissolve clocks ──────────────────────────────────────────────

/// Leaves the body visible through its first floor bounce.
const double dissolveSeconds = 1.1;
const double dissolveDelaySeconds = 1.25;
const double deathSinkDepth = 2.2;

// ── Death: the physics corpse ───────────────────────────────────────────

/// After the hit flinch the body IS a physics object: a Rapier box
/// launched with the blow, bouncing and tumbling against the ground
/// collider until it rests.
final Vector3 corpseHalfExtents = Vector3(0.45, 1.2, 0.35);
const double corpseHitSeconds = 0.08;
const double corpseLaunchSpeed = 7.0;
const double corpseHopVelocity = 5.2;
const double corpseTumbleFactor = 1.1;
const double corpseTumbleMin = 5.5;
const double corpseYawSpin = 1.8;
const double corpseLinearDamping = 0.25;
const double corpseAngularDamping = 0.9;

/// The dropped axe: its own physics object, tossed clear of the body.
final Vector3 axeHalfExtents = Vector3(0.06, 0.42, 0.06);
const double axeDropCarry = 0.55;
const double axeDropToss = 2.6;
const double axeDropSpin = 9.0;

/// Ground dust when the corpse (or a bounce) slams down: it needs a real
/// fall behind it, and only the first few impacts smoke.
const double corpseDustMinFallSpeed = 3.0;
const int corpseDustMaxBursts = 2;

/// Rapier owns both the bounce and the floor grip.
const PhysicsMaterial corpseMaterial = PhysicsMaterial(
  friction: 1,
  restitution: 0.8,
  density: 1.5,
);

// ── Animation: blends & strides ─────────────────────────────────────────

const double brawlerLocomotionFadeSeconds = 0.001;
const double brawlerOneShotFadeSeconds = 0.001;

const double brawlerWalkStrideSpeed = 2.3;
const double brawlerRunStrideSpeed = 5.2;
const double brawlerStrafeStrideSpeed = 3.2;

/// Walk blends into run at this ground speed.
const double brawlerRunBlendSpeed = 3.4;

// ── Animation: authored clip lengths & playback windows ─────────────────

const double chopClipSeconds = 1.63;
const double hitBClipSeconds = 0.87;
const double deathBClipSeconds = 2.63;

const double risingSeconds = 2.30;
const double awakenClipSeconds = 2.30;

const double tauntSeconds = 1.03;
const double tauntClipSeconds = 1.033;
const double tauntIntervalSeconds = 7.0;

const double brawlerFlinchSeconds = 0.32;

const double airborneProneRate = 5.0;
const double proneSettleRate = 2.6;

// ── Material tells ──────────────────────────────────────────────────────

final Vector4 telegraphEmissive = Vector4(1.0, 0.42, 0.12, 1);
