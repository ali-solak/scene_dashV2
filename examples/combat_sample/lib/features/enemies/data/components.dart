part of '../enemies.dart';

/// Tags every enemy entity.
final class Enemy implements Tag {
  const Enemy();
}

enum BrawlPhase {
  /// Climbing out of the ground on spawn (the floor-rise). Held still and
  /// harmless-looking until it finishes, then straight to [approach].
  rising,
  approach,
  circle,
  taunting,
  telegraph,
  swing,
  recover,

  /// Rolling clear of a swing the player just committed to.
  dodging,
  staggered,
  dying,
}

/// The barbarian's brain: one [Machine] owns the mode; a fixed telegraph
/// always precedes a swing. Rhythm constants are deliberately distinct
/// from the player's.
final class Brawler {
  Brawler({
    required this.slot,
    required this.circleDirection,
    required this.wobbleSeed,
    this.power = 1,
    this.tempo = 1,
    this.giant = false,
  }) : // Giants do not climb out of the ground; they walk in normal-sized
       // and swell on the transform clip, so a giant starts already up
       // (`approach`) and the awaken rise is for ordinary barbarians only.
       phase = Machine<BrawlPhase>(
         giant ? BrawlPhase.approach : BrawlPhase.rising,
       );

  /// Spawn index within the wave (drives the circle direction and wobble).
  final int slot;

  /// Damage/knockback multiplier: waves scale it, giants multiply it.
  final double power;

  /// Attack-speed multiplier: later waves wind up, recover, and re-engage
  /// faster, so the pressure rises even at the same damage. Divides every
  /// phase window, so `1` is the authored rhythm and `1.5` is half again
  /// as fast.
  final double tempo;

  /// A giant: bigger, tougher, and its blows launch the player.
  final bool giant;

  final Machine<BrawlPhase> phase;

  /// Seconds spent circling since the last taunt; the mid-fight taunt
  /// fires off this, so the pack heckles on a timer.
  double sinceTaunt = 0;

  /// Seconds since a non-staggering connect (a fire-gush or lava tick).
  /// The mapper reads it for a brief flinch; it gates nothing, so a body
  /// on fire still circles and swings. Starts spent.
  double sinceHurt = double.infinity;

  /// +1 or -1: which way this one circles the player.
  final double circleDirection;

  /// Phase offset for the circling radius wobble, so the pack breathes
  /// instead of orbiting in lockstep.
  final double wobbleSeed;

  /// Accumulated circling time driving the wobble (advanced by movement).
  double wobble = 0;

  /// The current chop's windup. A combo opener winds up slower (the tell),
  /// its follow-up faster, so one constant cannot serve both.
  double windup = telegraphSeconds;

  /// Chops still queued after the current one.
  int comboLeft = 0;

  /// Bumped when a chop's windup starts. A combo never leaves the attack
  /// pose, so this is what tells the mapper to replay the clip.
  int chopIndex = 0;

  /// Seconds since this one last rolled clear. Starts spent, so an opener
  /// can be dodged.
  double sinceDodge = double.infinity;

  /// Which way the current dodge rolls: +1 left, -1 right.
  double dodgeSign = 1;

  /// Facing yaw; forward is `(sin facing, 0, cos facing)`. Frozen from the
  /// swing on, so a roll sidesteps a committed arc.
  double facing = 0;

  /// Pitch the body tumbles through while a wind blast has it in the air.
  /// Snaps flat on landing.
  double tumble = 0;

  /// Thrown, or still on the floor from it; mirrors
  /// `Knockback.incapacitated` for the animation mapper.
  bool downed = false;

  /// Still in the air (a subset of [downed]): true through the wind-blast
  /// arc, false once it lands. Lets the mapper show a real airborne pose,
  /// then the floor pose on the landing beat.
  bool airborne = false;

  /// Mirror of the coordinator's grant (single writer: [coordinateAggro]).
  /// The holder closes in and may telegraph; everyone else circles.
  bool hasToken = false;

  /// World-space velocity this step (written by movement, read by the
  /// animation mapper).
  final Vector3 velocity = Vector3.zero();
}

/// slow down enemies in lava pit
final class Mired {
  const Mired();
}

/// A barbarian's in-world health bar: a `WidgetComponent` surface on a
/// child [node] above the head, its fill pushed each frame into
/// [fraction] and the node yaw-aimed at the camera.
final class EnemyHealthBar {
  EnemyHealthBar({required this.fraction, required this.node});

  final ValueNotifier<double> fraction;
  final Node node;

  /// Last fraction pushed; a drop means a hit, which starts the punch.
  double lastFraction = 1;

  /// Seconds since the last hit, driving the scale-pop-and-tilt in
  /// [updateHealthBars]. Starts spent so a fresh bar sits still.
  double sinceHit = double.infinity;
}

/// The aggro token: at most one barbarian may telegraph at a time, which
/// keeps the fight readable. Granted by [coordinateAggro]; returned on
/// recover/stagger/death with a cooldown before the next grant.
final class AggroCoordinator {
  Entity? holder;
  double cooldown = 0;
}

/// A giant mid-transformation: added with `removeAfter:` so the
/// framework timer drives both the clip and the growth. While present
/// the barbarian holds still and swells from normal size to [giantScale].
final class Transforming {
  const Transforming();
}

/// Which pooled barbarian model this enemy borrowed. Released back to
/// the pool by an `onRemove` observer when the entity despawns, so waves
/// can keep reusing a small set of imported (un-cloneable) skinned models.
final class ModelSlot {
  const ModelSlot(this.index, {this.axe});

  final int index;
  final Node? axe;
}

/// Marks a dying barbarian's death window. Added with `removeAfter:` so
/// the framework timer drives the effect: the death system maps
/// `expiryOf<Dissolving>` onto the sink-and-shrink progress.
final class Dissolving {
  const Dissolving();
}

/// Short hit-reaction delay before the physics handoff.
final class PendingCorpse {
  const PendingCorpse();
}

/// A corpse handed to Rapier, kept so the dust system can watch the body
/// slam into the ground.
final class PhysicsCorpse {
  PhysicsCorpse(this.body);

  final RapierRigidBody body;

  /// Last frame's vertical velocity; a hard fall going flat is a landing.
  double fallSpeed = 0;

  /// Puffs spent, so a long bounce chain does not smoke forever.
  int bursts = 0;
}

/// The body's scene handles: the model wrapper node the death effect
/// sinks (base transform captured so a restart puts it back), plus, for
/// the graybox capsule fallback only, its private material for the
/// emissive telegraph tell.
final class BrawlerVisuals {
  BrawlerVisuals({required this.bodyRoot, this.capsuleMaterial})
    : _baseTransform = bodyRoot.localTransform.clone();

  /// The scaled model wrapper (character) or the capsule body node.
  final Node bodyRoot;
  final Matrix4 _baseTransform;
  final PhysicallyBasedMaterial? capsuleMaterial;

  /// The corpse's exit: it sinks, at full size, until the ground has it.
  /// [progress] runs 0 to 1 across the dissolve window; the body descends
  /// by [sink] over it, eased so it slips under rather than dropping.
  void applyDeath(double progress, double sink) {
    final eased = progress * progress;
    bodyRoot.localTransform =
        Matrix4.translation(Vector3(0, -sink * eased, 0)) * _baseTransform;
  }

  /// The giant's growth: [factor] 1 leaves the body at its (giant) base
  /// scale, so the transformation ramps from `1 / giantScale` up to 1.
  void applyGrowth(double factor) {
    bodyRoot.localTransform =
        _baseTransform * Matrix4.diagonal3(Vector3.all(factor));
  }

  void hide() => bodyRoot.visible = false;
}
