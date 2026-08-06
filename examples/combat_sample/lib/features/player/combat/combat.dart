/// Player combat state.
library;

import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../../../common/actors.dart' show CastLeap;

enum CombatPhase { idle, startup, active, recovery, rolling, staggered }

enum CombatAction { attack, roll }

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

const double heavyHitInterval = 0.30;
const double rollSeconds = 0.45;
const double iFrameStart = 0.05;
const double iFrameEnd = 0.32;
const double staggerSeconds = 0.35;

const double bufferWindow = 0.75;

// Heavy attack

const double heavyThresholdSeconds = 0.22;

const double heavyStartupSeconds = 0.62;

const double lightDamage = 25;

const double heavyDamage = 14;

const double lightKnockback = 3.5;
const double heavyKnockback = 2.5;

final class Fighter {
  final phase = Machine<CombatPhase>(CombatPhase.idle);

  bool heavy = false;
  int strikeHits = 0;

  Stance stance = Stance.free;

  double sinceHurt = double.infinity;
  double sinceCast = double.infinity;

  bool get iFramed =>
      phase.state == CombatPhase.rolling &&
      phase.elapsed >= iFrameStart &&
      phase.elapsed < iFrameEnd;
}

void fighterDriver(World world) {
  final buffer = world.buffer<CombatAction>();
  final held = world.buttons<CombatAction>().pressed(CombatAction.attack);
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
        final window = fighter.heavy ? heavyActiveSeconds : activeSeconds;
        if (phase.elapsed >= window) phase.go(CombatPhase.recovery);
      case CombatPhase.recovery:
        final tail = fighter.heavy ? heavyRecoverySeconds : recoverySeconds;
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

void clearBufferOnStagger(World world) {
  final buffer = world.buffer<CombatAction>();
  world.query<Fighter>().each((entity, fighter) {
    if (fighter.phase.justEntered(CombatPhase.staggered)) buffer.clear();
  });
}
