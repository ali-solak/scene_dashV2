/// Player combat state.
library;

import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

enum CombatPhase { idle, startup, active, recovery, rolling, staggered }

/// Player combat input.
enum CombatAction { attack, roll }

/// Fighter movement stance.
enum Stance { free, locked }

// Combat timing

const double combatFixedDt = 1 / 60;

// Light attack timing
const double startupSeconds = 0.18;
const double activeSeconds = 0.12;
const double recoverySeconds = 0.41;

// Heavy attack timing
const double heavyActiveSeconds = 1.20;
const double heavyRecoverySeconds = 0.60;

/// Seconds between spin hits.
const double heavyHitInterval = 0.30;
const double rollSeconds = 0.45;
const double iFrameStart = 0.05;
const double iFrameEnd = 0.32;
const double staggerSeconds = 0.35;

/// Input buffer duration.
const double bufferWindow = 0.75;

// Heavy attack

/// Hold duration that commits a heavy attack.
const double heavyThresholdSeconds = 0.22;

/// Heavy attack windup.
const double heavyStartupSeconds = 0.62;

const double lightDamage = 25;

/// Damage per spin hit.
const double heavyDamage = 14;

/// Knockback speed on hit.
const double lightKnockback = 3.5;
const double heavyKnockback = 2.5;

/// Player combat state.
final class Fighter {
  final phase = Machine<CombatPhase>(CombatPhase.idle);

  /// Whether the current attack is heavy.
  bool heavy = false;

  /// Hits emitted during the current attack.
  int strikeHits = 0;

  Stance stance = Stance.free;

  /// Seconds since the last damaging hit.
  double sinceHurt = double.infinity;

  /// Seconds since the last leaping skill.
  double sinceCast = double.infinity;

  bool get iFramed =>
      phase.state == CombatPhase.rolling &&
      phase.elapsed >= iFrameStart &&
      phase.elapsed < iFrameEnd;
}

final class HitLanded {
  final Entity target;
  final double damage;
  final bool heavy;

  /// World space knockback.
  final Vector3? knockback;

  /// Whether the hit interrupts the victim.
  final bool stagger;

  /// Whether the hit creates impact effects.
  final bool impact;

  const HitLanded(
    this.target,
    this.damage, {
    this.heavy = false,
    this.knockback,
    this.stagger = true,
    this.impact = true,
  });
}

/// Signals a leaping skill cast.
final class CastLeap {
  const CastLeap();
}

/// Ticks each fighter's machine, then transitions on time and buffered
/// intent. A quick press goes active at [startupSeconds] on release; a
/// press still held at [heavyThresholdSeconds] commits the heavy, which
/// goes active at [heavyStartupSeconds] regardless of release.
void fighterDriver(World world) {
  final buffer = world.buffer<CombatAction>();
  final held = world.buttons<CombatAction>().pressed(CombatAction.attack);
  // Track leaping casts.
  final leapt = world.events<CastLeap>().isNotEmpty;
  world.query<Fighter>().each((entity, fighter) {
    fighter.sinceHurt += world.dt;
    fighter.sinceCast += world.dt;
    if (leapt) fighter.sinceCast = 0;
    final phase = fighter.phase..tick(world.dt);
    switch (phase.state) {
      case CombatPhase.idle:
        if (buffer.consume(CombatAction.attack)) {
          fighter.heavy = false;
          phase.go(CombatPhase.startup);
        } else if (buffer.consume(CombatAction.roll)) {
          phase.go(CombatPhase.rolling);
        }
      case CombatPhase.startup:
        if (!fighter.heavy && held && phase.elapsed >= heavyThresholdSeconds) {
          fighter.heavy = true;
        }
        final windup = fighter.heavy ? heavyStartupSeconds : startupSeconds;
        if (phase.elapsed >= windup && (fighter.heavy || !held)) {
          phase.go(CombatPhase.active);
        }
      case CombatPhase.active:
        // Select the attack window.
        final window = fighter.heavy ? heavyActiveSeconds : activeSeconds;
        if (phase.elapsed >= window) phase.go(CombatPhase.recovery);
      case CombatPhase.recovery:
        final tail = fighter.heavy ? heavyRecoverySeconds : recoverySeconds;
        // Allow roll recovery cancels.
        if (buffer.consume(CombatAction.roll)) {
          phase.go(CombatPhase.rolling);
        } else if (phase.elapsed >= tail) {
          phase.go(CombatPhase.idle);
        }
      case CombatPhase.rolling:
        if (phase.elapsed >= rollSeconds) phase.go(CombatPhase.idle);
      case CombatPhase.staggered:
        if (phase.elapsed >= staggerSeconds) phase.go(CombatPhase.idle);
    }
  });
}

/// Clears buffered input when staggered.
void clearBufferOnStagger(World world) {
  final buffer = world.buffer<CombatAction>();
  world.query<Fighter>().each((entity, fighter) {
    if (fighter.phase.justEntered(CombatPhase.staggered)) buffer.clear();
  });
}
