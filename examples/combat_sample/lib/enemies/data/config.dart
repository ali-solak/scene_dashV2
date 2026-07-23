part of '../enemies.dart';

const double enemyMaxHealth = 50;

// --- Giants (the transform) ---

/// A giant is this much bigger than a normal barbarian, and its blows
/// launch the player rather than merely shoving them.
const double giantScale = 1.7;
const double giantHealthFactor = 3.5;
const double giantPower = 2.2;

/// Upward velocity a giant's connect puts on the player (the "fly").
const double giantLaunchSpeed = 12.5;

/// The window the growth and the transform clip share (one `removeAfter:`
/// clock drives both). Longer than the 1.0 s clip so it plays at ~0.6x:
/// a giant swelling should feel like effort.
const double giantTransformSeconds = 1.7;
const double transformClipSeconds = 1.0;

/// Points a kill pays: a giant is worth several ordinary barbarians.
const int enemyPoints = 10;
const int giantPoints = 50;

const double enemyCapsuleRadius = 0.48;
const double enemyCapsuleHeight = 0.8;

/// The in-world health bar's lift above the feet, and its world height.
/// The widget's 240x64 canvas makes it ~3.75x as wide, so the height sets
/// the whole footprint. The lift clears the taller 2.45 u barbarian.
const double healthBarHeight = 3;
const double healthBarWorldHeight = 0.2;

/// The bar's hit punch: how long it lasts, how much bigger it pops, and
/// how far it slash-tilts (rad, in the screen plane). Big on purpose: the
/// bar is small on screen, so a timid reaction reads as nothing.
const double healthBarShakeSeconds = 0.3;
const double healthBarShakePop = 0.45;
const double healthBarShakeTilt = 0.22;

// --- The brawl rhythm (distinct from the player's, so beats interleave) ---

// Scaled with the 2.6 u fighters: bigger bodies need bigger orbits and
// faster closing, or the fight reads as slow-motion shuffling.
const double approachSpeed = 4.2;
const double circleSpeed = 2.3;

/// Ground speed of a [Mired] body (in a lava pit) as a fraction of
/// normal: a hard slog, so the pit reads as a trap to wade around rather
/// than a patch you stroll across.
const double miredSpeedFactor = 0.32;

/// Orbit radius while circling; the wobble breathes around it.
const double circleRadius = 4.4;
const double circleWobbleAmplitude = 0.7;
const double circleWobbleRate = 0.7;

/// Inside this range an approaching barbarian settles into the circle.
const double engageRange = 6.2;

/// The token holder's closing speed (circle → strike range).
const double tokenCloseSpeed = 3.6;

/// The token holder telegraphs once within this range. Must sit inside
/// the swing's reach (rules' `brawlerReach` 3.0); the telegraph roots
/// the body, so an out-of-reach telegraph would whiff every time.
const double brawlerAttackRange = 2.6;

/// The readability contract: a fixed, visible windup before every swing.
/// The telegraph stays long (it must be readable); the swing itself is
/// quick so the strike lands like a strike.
const double telegraphSeconds = 0.6;
const double swingSeconds = 0.18;
const double recoverSeconds = 0.75;

/// Long enough that a thrown barbarian is still on the floor for a beat
/// after it lands, rather than bouncing straight up into a swing.
const double brawlStaggerSeconds = 0.8;

const double brawlerDamage = 15;

/// Cooldown between the token returning and the next grant.
const double aggroCooldownSeconds = 1.2;

/// The death window's back half: the sink.
/// Invariant: `dissolveDelaySeconds + dissolveSeconds` must stay under
/// the wave breather (`waveIntermissionSeconds`, 3.0). A corpse holds its
/// pooled model until despawn; overshoot and the next wave's barbarians
/// fall back to graybox capsules.
const double dissolveSeconds = 1.8;

/// How long the corpse lies before the sink starts (the `Dissolving`
/// clock runs delay + dissolve; the body is untouched through the delay).
const double dissolveDelaySeconds = 0.7;

/// How far the dying body sinks into the ground. Deep enough to swallow
/// a body lying on its side: the corpse sinks at full size, so this has
/// to clear the ragdoll's height rather than just dip it.
const double deathSinkDepth = 2.2;

// --- Ragdoll (Rapier owns the corpse) ---

/// The corpse's collider: a box, not a capsule. A vertical capsule
/// settles upright ("stands up" after death); a box tips and lies on a
/// face. Sized to the 2.45 u barbarian.
final Vector3 corpseHalfExtents = Vector3(0.45, 1.2, 0.35);

/// The send-off: the killing blow's shove plus a hop, and a tumble about
/// the axis perpendicular to it, so the body pitches over as it flies.
const double corpseHopVelocity = 3.4;
const double corpseTumbleFactor = 1.6;

/// No friction on these colliders, so damping is the corpse's only
/// brake. High enough that it tumbles, skids briefly and stops instead
/// of gliding along the ground.
const double corpseLinearDamping = 2.4;
const double corpseAngularDamping = 1.4;

/// How long a corpse is allowed to tumble before it is frozen in place.
/// Long enough to see it land and roll; short enough that it never
/// wanders.
const double corpseSettleSeconds = 1.4;

/// How much of the killing blow's shove the ragdoll inherits, so a corpse
/// flies off the hit rather than dropping straight down. Under 1: the
/// full shove is tuned for a living fighter and would skate the corpse
/// off the arena.
const double corpseLaunchFactor = 0.45;

// --- Animation mapper ---

// Hard snap, same as the player's config: crossfades pancaked the pose,
// and barbarians have more clips sharing the same joints than the player.
const double brawlerLocomotionFadeSeconds = 0.001;
const double brawlerOneShotFadeSeconds = 0.001;

/// Authored ground speeds of the loop clips, for stride sync; scaled
/// with the 2.45 u barbarian so the feet stop sliding.
const double brawlerWalkStrideSpeed = 2.3;
const double brawlerRunStrideSpeed = 5.2;
const double brawlerStrafeStrideSpeed = 3.2;

/// Above this speed the run clip takes over from the walk.
const double brawlerRunBlendSpeed = 3.4;

/// Clip lengths (docs/asset_inventory.md).
const double chopClipSeconds = 1.63;
const double hitBClipSeconds = 0.87;
const double deathBClipSeconds = 2.63; // Death_B (barbarian collapse)

// --- Spawn rise + mid-fight taunt ---

/// How long a barbarian spends climbing out of the ground before it can
/// move. The full Skeletons_Awaken_Floor, so the rise reads as a rise and
/// not a twitch; a wave opens with the pack hauling itself upright.
const double risingSeconds = 2.30;
const double awakenClipSeconds = 2.30; // Skeletons_Awaken_Floor

/// The mid-fight taunt: how long it holds the barbarian still, and
/// the base gap between one circling non-holder's taunts (jittered per
/// brawler so the pack does not taunt in unison).
const double tauntSeconds = 1.03;
const double tauntClipSeconds = 1.033; // Skeletons_Taunt
const double tauntIntervalSeconds = 7.0;

/// How long the fire/lava flinch reaction shows before locomotion takes
/// back over. Short: a jolt, not a stagger. A pit tick lands more often
/// than this, so a body standing in lava keeps flinching.
const double brawlerFlinchSeconds = 0.32;

/// Radians per second a thrown body turns over onto its back. Slow
/// enough to see it happen across the arc, fast enough to be flat by the
/// time it lands.
const double proneSettleRate = 2.6;

/// Telegraph tell color (emissive ramp on the body).
final Vector4 telegraphEmissive = Vector4(1.0, 0.42, 0.12, 1);
