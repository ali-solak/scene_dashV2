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

/// The transformation: EXPERIMENTAL_Medium_Transform is 1.00 s, and the
/// body swells from normal size to [giantScale] across exactly that
/// window (the clip and the growth share one `removeAfter:` clock).
/// The window the growth and the clip share. LONGER than the clip, so
/// the transformation plays at ~0.6x — a giant swelling should feel like
/// effort, and at 1:1 the clip simply stopped dead on its last frame.
const double giantTransformSeconds = 1.7;
const double transformClipSeconds = 1.0;

/// Points a kill pays: a giant is worth several ordinary barbarians.
const int enemyPoints = 10;
const int giantPoints = 50;

const double enemyCapsuleRadius = 0.48;
const double enemyCapsuleHeight = 0.8;

/// The in-world health bar sits this high above the barbarian's feet, at
/// this world height (task 17). Small — the widget's 240×64 canvas makes
/// it ~3.75× as wide, so this height sets the whole footprint. Raised to
/// clear the taller 2.45 u barbarian.
const double healthBarHeight = 3;
const double healthBarWorldHeight = 0.2;

// --- The brawl rhythm (distinct from the player's, so beats interleave) ---

// Scaled with the 2.6 u fighters: bigger bodies need bigger orbits and
// faster closing, or the fight reads as slow-motion shuffling.
const double approachSpeed = 4.2;
const double circleSpeed = 2.3;

/// Orbit radius while circling; the wobble breathes around it.
const double circleRadius = 4.4;
const double circleWobbleAmplitude = 0.7;
const double circleWobbleRate = 0.7;

/// Inside this range an approaching barbarian settles into the circle.
const double engageRange = 6.2;

/// The token holder's closing speed (circle → strike range).
const double tokenCloseSpeed = 3.6;

/// The token holder telegraphs once within this range. Must sit inside
/// the swing's reach (rules' `brawlerReach` 3.0) — the telegraph roots
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

/// The death window's back half — the sink.
///
/// INVARIANT: `dissolveDelaySeconds + dissolveSeconds` must stay under
/// the wave breather (`waveIntermissionSeconds`, 3.0). A corpse holds its
/// pooled model until it despawns, so a death window longer than the
/// breather means wave N's corpses are still holding models when wave
/// N+1 walks in — and the barbarians that miss out fall back to graybox
/// CAPSULES. At 2.6 the total was 3.3 against a 3.0 breather, which is
/// exactly the overlap that produced them.
const double dissolveSeconds = 1.8;

/// Death restage: the fall clip plays and the corpse lies for this long
/// BEFORE the sink-and-shrink starts (the `Dissolving` clock runs
/// delay + dissolve; the body is untouched through the delay). Short so
/// the effect is clearly seen, not a long-delayed vanish.
const double dissolveDelaySeconds = 0.7;

/// How far the dying body sinks into the ground as it shrinks away
/// (the fallback when the corpse never got a physics body).
/// Deep enough to swallow a body lying on its side — the corpse sinks at
/// full size now (no shrink), so this has to clear the ragdoll's height
/// rather than just dip it.
const double deathSinkDepth = 2.2;

// --- Ragdoll (Rapier owns the corpse) ---

/// The corpse's collider: a BOX, not a capsule — a vertical capsule
/// settles upright ("stands up" after death); a box tips and lies on a
/// face. Sized to the 2.45 u barbarian.
final Vector3 corpseHalfExtents = Vector3(0.45, 1.2, 0.35);

/// The send-off: the killing blow's shove plus a hop, and a tumble about
/// the axis perpendicular to it, so the body pitches over as it flies.
const double corpseHopVelocity = 3.4;
const double corpseTumbleFactor = 1.6;

/// Rapier has no friction on these colliders, so DAMPING is the only
/// brake a corpse has. At 0.25 a body carrying a heavy hit's shove kept
/// coasting along the ground long after it should have settled — the
/// "dead enemies glide". High enough now that it tumbles, skids briefly
/// and stops.
const double corpseLinearDamping = 2.4;
const double corpseAngularDamping = 1.4;

/// How long a corpse is allowed to tumble before it is frozen in place.
/// Long enough to see it land and roll; short enough that it never
/// wanders.
const double corpseSettleSeconds = 1.4;

/// How much of the killing blow's shove the ragdoll inherits. The blow
/// is tuned to throw a LIVING fighter around; handing all of it to a
/// corpse that then has to slow itself down under damping alone sends it
/// skating across the clearing.
const double corpseLaunchFactor = 0.45;

// --- Animation mapper (task 15, barbarian archetype) ---

// Back to the hard snap — see the player's config. The barbarians were
// the ones that pancaked first and worst, which is a clue in itself:
// they have more clips sharing the same joints than the player does.
const double brawlerLocomotionFadeSeconds = 0.001;
const double brawlerOneShotFadeSeconds = 0.001;

/// Authored ground speeds of the loop clips, for stride sync — scaled
/// with the 2.45 u barbarian so the feet stop sliding.
const double brawlerWalkStrideSpeed = 2.3;
const double brawlerRunStrideSpeed = 5.2;
const double brawlerStrafeStrideSpeed = 3.2;

/// Above this speed the run clip takes over from the walk.
const double brawlerRunBlendSpeed = 3.4;

/// Clip lengths (docs/asset_inventory.md).
const double chopClipSeconds = 1.63;
const double hitBClipSeconds = 0.87;
const double deathBClipSeconds = 2.63;

/// Radians per second a thrown body turns over onto its back. Slow
/// enough to see it happen across the arc, fast enough to be flat by the
/// time it lands.
const double proneSettleRate = 2.6;

/// Telegraph tell color (emissive ramp on the body — L3's first consumer).
final Vector4 telegraphEmissive = Vector4(1.0, 0.42, 0.12, 1);
