part of '../projectiles.dart';

enum BlasterPhase { ready, charging, bursting, cooldown }

final class BlasterShots {
  const BlasterShots({this.burst = 0, this.charged});

  final int burst;

  final double? charged;

  bool get isEmpty => burst == 0 && charged == null;

  static const none = BlasterShots();
}

final class Blaster {
  Blaster() {
    _recovery.tick(blasterCooldown);
  }

  final Machine<BlasterPhase> phase = Machine(BlasterPhase.ready);

  final GameTimer _recovery = GameTimer(blasterCooldown);

  // Burst pellets form a timed emission queue.
  int _queuedBurst = 0;
  double _burstTimer = 0;

  double get charge01 {
    if (phase.state != BlasterPhase.charging) return 0;
    const span = blasterMaxChargeDuration - blasterChargeThreshold;
    return ((phase.elapsed - blasterChargeThreshold) / span).clamp(0.0, 1.0);
  }

  double get cooldown01 => 1 - _recovery.fraction;

  bool get isCharging =>
      phase.state == BlasterPhase.charging &&
      phase.elapsed >= blasterChargeThreshold;

  bool get isCoolingDown => !_recovery.finished;

  bool get isReady => phase.state == BlasterPhase.ready;

  BlasterShots update({
    required bool pressed,
    required bool released,
    required bool canceled,
    required bool held,
    required double dt,
  }) {
    phase.tick(dt);
    _recovery.tick(dt);
    if (phase.state == BlasterPhase.cooldown && _recovery.finished) {
      phase.go(BlasterPhase.ready);
    }

    double? charged;

    if (pressed && phase.state == BlasterPhase.ready) {
      phase.go(BlasterPhase.charging);
    }

    if (phase.state == BlasterPhase.charging) {
      if (canceled) {
        phase.go(BlasterPhase.ready);
      } else if (released) {
        if (phase.elapsed >= blasterChargeThreshold) {
          charged = charge01;
          _startCooldown(chargedShotCooldown);
        } else {
          _startBurst();
        }
      } else if (!held) {
        phase.go(BlasterPhase.ready);
      }
    }

    final burst = _emitBurstPellets(dt);
    if (charged != null) return BlasterShots(charged: charged);
    if (burst > 0) return BlasterShots(burst: burst);
    return BlasterShots.none;
  }

  void _startBurst() {
    phase.go(BlasterPhase.bursting);
    _queuedBurst = blasterBurstShots;
    _burstTimer = 0;
    _recovery.reset(blasterCooldown);
  }

  void _startCooldown(double duration) {
    phase.go(BlasterPhase.cooldown);
    _recovery.reset(duration);
  }

  int _emitBurstPellets(double dt) {
    if (phase.state != BlasterPhase.bursting) return 0;
    var fired = 0;
    _burstTimer -= dt;
    while (_queuedBurst > 0 && _burstTimer <= 0) {
      _queuedBurst--;
      fired++;
      _burstTimer += blasterBurstInterval;
    }
    if (_queuedBurst == 0) {
      phase.go(_recovery.finished ? BlasterPhase.ready : BlasterPhase.cooldown);
    }
    return fired;
  }

  void reset() {
    phase.go(BlasterPhase.ready);
    _recovery
      ..reset()
      ..tick(_recovery.duration);
    _queuedBurst = 0;
    _burstTimer = 0;
  }
}

final class Projectile {
  Projectile({this.charge = 0});

  final double charge;

  /// Rocks already hit by this charged shot.
  final Set<Entity> hitRocks = <Entity>{};

  bool get charged => charge > 0;
}
