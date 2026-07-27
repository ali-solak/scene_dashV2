part of '../enemies.dart';

/// Tags every enemy entity.
final class Enemy implements Tag {
  const Enemy();
}

enum BrawlPhase {
  /// Climbing out of the ground.
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

/// Enemy combat state and timing.
final class Brawler {
  Brawler({
    required this.slot,
    required this.circleDirection,
    required this.wobbleSeed,
    this.power = 1,
    this.tempo = 1,
    this.giant = false,
  }) : phase = Machine<BrawlPhase>(
         giant ? BrawlPhase.approach : BrawlPhase.rising,
       );

  /// Spawn index within the wave.
  final int slot;

  /// Damage and knockback multiplier.
  final double power;

  /// Attack speed multiplier.
  final double tempo;

  /// Whether this enemy is a giant.
  final bool giant;

  final Machine<BrawlPhase> phase;

  /// Seconds since the last taunt.
  double sinceTaunt = 0;

  /// Seconds since the last non-staggering hit.
  double sinceHurt = double.infinity;

  /// +1 or -1: which way this one circles the player.
  final double circleDirection;

  /// Circling wobble offset.
  final double wobbleSeed;

  /// Accumulated circling time driving the wobble (advanced by movement).
  double wobble = 0;

  /// Current attack windup.
  double windup = telegraphSeconds;

  /// Chops still queued after the current one.
  int comboLeft = 0;

  /// Current chop number.
  int chopIndex = 0;

  /// Seconds since the last dodge.
  double sinceDodge = double.infinity;

  /// Which way the current dodge rolls: +1 left, -1 right.
  double dodgeSign = 1;

  /// Facing yaw.
  double facing = 0;

  /// Pitch the body tumbles through while a wind blast has it in the air.
  /// Snaps flat on landing.
  double tumble = 0;

  /// Thrown, or still on the floor from it; mirrors
  /// `Knockback.incapacitated` for the animation mapper.
  bool downed = false;

  /// Whether a downed enemy is airborne.
  bool airborne = false;

  /// Whether this enemy has the aggro token.
  bool hasToken = false;

  /// World space velocity this step.
  final Vector3 velocity = Vector3.zero();
}

/// Slows enemies in lava.
final class Mired {
  const Mired();
}

/// Enemy health bar scene data.
final class EnemyHealthBar {
  EnemyHealthBar({required this.fraction, required this.node});

  final ValueNotifier<double> fraction;
  final Node node;

  /// Last displayed health.
  double lastFraction = 1;

  /// Seconds since the last hit.
  double sinceHit = double.infinity;
}

/// Coordinates the active attacker.
final class AggroCoordinator {
  Entity? holder;
  double cooldown = 0;
}

/// Marks a giant transformation.
final class Transforming {
  const Transforming();
}

/// Borrowed enemy model.
final class ModelSlot {
  const ModelSlot(this.index, {this.axe});

  final int index;
  final Node? axe;
}

/// Marks the dissolve window.
final class Dissolving {
  const Dissolving();
}

/// Short hit-reaction delay before the physics handoff.
final class PendingCorpse {
  const PendingCorpse();
}

/// Physics corpse state.
final class PhysicsCorpse {
  PhysicsCorpse(this.body);

  final RigidBody body;

  /// Last vertical velocity.
  double fallSpeed = 0;

  /// Dust bursts used.
  int bursts = 0;
}

/// Enemy scene handles.
final class BrawlerVisuals {
  BrawlerVisuals({required this.bodyRoot, this.capsuleMaterial})
    : _baseTransform = bodyRoot.localTransform.clone();

  /// The scaled model wrapper (character) or the capsule body node.
  final Node bodyRoot;
  final Matrix4 _baseTransform;
  final PhysicallyBasedMaterial? capsuleMaterial;

  /// Applies the death sink.
  void applyDeath(double progress, double sink) {
    final eased = progress * progress;
    bodyRoot.localTransform =
        Matrix4.translation(Vector3(0, -sink * eased, 0)) * _baseTransform;
  }

  /// Applies giant growth.
  void applyGrowth(double factor) {
    bodyRoot.localTransform =
        _baseTransform * Matrix4.diagonal3(Vector3.all(factor));
  }

  void hide() => bodyRoot.visible = false;
}
