part of '../enemies.dart';

final class Enemy implements Tag {
  const Enemy();
}

enum BrawlPhase {
  rising,
  approach,
  circle,
  taunting,
  telegraph,
  swing,
  recover,

  dodging,
  staggered,
  dying,
}

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

  final int slot;
  final double power;
  final double tempo;
  final bool giant;

  final Machine<BrawlPhase> phase;

  double sinceTaunt = 0;
  double sinceHurt = double.infinity;

  /// +1 or -1: which way this one circles the player.
  final double circleDirection;

  final double wobbleSeed;
  double wobble = 0;
  double windup = telegraphSeconds;
  int comboLeft = 0;
  int chopIndex = 0;
  double sinceDodge = double.infinity;

  /// Which way the current dodge rolls: +1 left, -1 right.
  double dodgeSign = 1;

  double facing = 0;

  /// Pitch the body tumbles through while a wind blast has it in the air.
  /// Snaps flat on landing.
  double tumble = 0;

  /// Thrown, or still on the floor from it; mirrors
  /// `Knockback.incapacitated` for the animation mapper.
  bool downed = false;

  bool airborne = false;
  bool hasToken = false;
  final Vector3 velocity = Vector3.zero();
}

final class Mired {
  const Mired();
}

final class EnemyHealthBar {
  EnemyHealthBar({required this.fraction, required this.node});

  final ValueNotifier<double> fraction;
  final Node node;

  double lastFraction = 1;
  double sinceHit = double.infinity;
}

final class AggroCoordinator {
  Entity? holder;
  double cooldown = 0;
}

final class Transforming {
  const Transforming();
}

final class ModelSlot {
  const ModelSlot(this.index, {this.axe});

  final int index;
  final Node? axe;
}

final class Dissolving {
  const Dissolving();
}

final class PendingCorpse {
  const PendingCorpse();
}

final class PhysicsCorpse {
  PhysicsCorpse(this.body);

  final RigidBody body;

  double fallSpeed = 0;
  int bursts = 0;
}

final class BrawlerVisuals {
  BrawlerVisuals({required this.bodyRoot, this.capsuleMaterial})
    : _baseTransform = bodyRoot.localTransform.clone();

  final Node bodyRoot;
  final Matrix4 _baseTransform;
  final PhysicallyBasedMaterial? capsuleMaterial;

  double _sink = 0;
  double _growth = 1;
  final Matrix4 _lean = Matrix4.identity();

  void applyDeath(double progress, double sink) {
    _sink = sink * progress * progress;
    _compose();
  }

  void applyGrowth(double factor) {
    _growth = factor;
    _compose();
  }

  void applyLean(Vector3 localDirection, double amount) {
    if (amount == 0 || localDirection.length2 < 1e-9) {
      if (_lean.isIdentity()) return;
      _lean.setIdentity();
    } else {
      _lean
        ..setIdentity()
        ..translateByVector3(localDirection * (amount * recoilDistance))
        ..rotate(
          Vector3(localDirection.z, 0, -localDirection.x),
          amount * recoilTilt,
        );
    }
    _compose();
  }

  void _compose() {
    bodyRoot.localTransform =
        Matrix4.translation(Vector3(0, -_sink, 0)) *
        _lean *
        _baseTransform *
        Matrix4.diagonal3(Vector3.all(_growth));
  }

  void hide() => bodyRoot.visible = false;
}
