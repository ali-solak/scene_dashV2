part of '../projectiles.dart';

enum BlasterPhase { ready, charging, bursting, cooldown }

/// Shots to spawn after advancing the [Blaster] one fixed step.
final class BlasterShots {
  const BlasterShots({this.burst = 0, this.charged});

  final int burst;

  /// Charged-shot strength in [0, 1], or null for none.
  final double? charged;

  bool get isEmpty => burst == 0 && charged == null;

  static const none = BlasterShots();
}

/// Tap-to-burst / hold-to-charge fire state machine — a component on the
/// player (attached fresh by an `OnEnter(playing)` system; the HUD reads
/// it back with `singleOrNull<Blaster>()`). The mode lives on a [Machine]
/// — `phase.elapsed` is the charge clock and transition edges replace
/// hand-rolled flags — while recovery stays a [GameTimer] (a genuine
/// duration spanning the bursting and cooldown states) and burst pellets
/// stay an emission queue.
final class Blaster {
  Blaster() {
    // Start with recovery fully served, so the blaster is ready and the
    // HUD shows no cooldown before the first shot.
    _recovery.tick(blasterCooldown);
  }

  /// The fire mode. [update] owns the tick; readers act on transition
  /// edges — `phase.justEntered(BlasterPhase.charging)` is the
  /// charging-started signal, readable until the next update.
  final Machine<BlasterPhase> phase = Machine(BlasterPhase.ready);

  /// Recovery after firing. The duration varies per shot type, so each
  /// fire resets it with the right target; it serves through both the
  /// bursting and cooldown states.
  final GameTimer _recovery = GameTimer(blasterCooldown);

  // Burst pellets are an emission queue (n shots at a fixed spacing, first
  // one immediately), not a plain timer, so their pacing stays hand-rolled.
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

  /// Advances the blaster one fixed step and returns the shots to spawn.
  BlasterShots update({
    required bool pressed,
    required bool released,
    required bool canceled,
    required bool held,
    required double dt,
  }) {
    // The machine ticks first — closing the previous edge window — so the
    // transitions below stay readable until the next update.
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
          charged = charge01; // Read before the phase leaves `charging`.
          _startCooldown(chargedShotCooldown);
        } else {
          _startBurst();
        }
      } else if (!held) {
        // Held dropped with no transition flag (focus loss mid-step): abort
        // so the blaster can't get stuck charging.
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

  /// Shot strength: `0.0` is a normal burst pellet; `(0, 1]` is a charged shot.
  /// Immutable for the projectile's life - hit force is derived from it.
  final double charge;

  /// Rock entities already hit by this charged projectile. Burst pellets
  /// despawn on first impact, so this remains empty for them. Keyed by
  /// [Entity] (index + generation), so a despawned rock's reused slot never
  /// aliases with a rock hit earlier in the flight.
  final Set<Entity> hitRocks = <Entity>{};

  bool get charged => charge > 0;
}
