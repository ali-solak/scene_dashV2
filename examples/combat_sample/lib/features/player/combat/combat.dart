/// Player combat state.
library;

import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../../../common/actors.dart' show CastLeap;
import '../../../common/inputs.dart' show MoveAxis;

enum CombatPhase {
  idle,
  startup,
  active,
  recovery,
  rolling,
  staggered,
  casting,
}

enum CombatAction { attack, heavy, roll }

enum Stance { free, locked }

enum CastPose { shoot, raise, block, leap }

// Combat timing

const double combatFixedDt = 1 / 60;

final class Swing {
  const Swing({
    required this.startup,
    required this.active,
    required this.recovery,
    required this.damage,
    required this.knockback,
    required this.lunge,
    this.hitInterval,
    this.sweepsAround = false,
    this.shockwave = false,
  });

  final double startup;
  final double active;
  final double recovery;
  final double damage;
  final double knockback;
  final double lunge;
  final double? hitInterval;
  final bool sweepsAround;
  final bool shockwave;

  double get lungeSeconds => hitInterval == null ? startup + active : startup;

  double get moveCancelSeconds => recovery * moveCancelFraction;
}

final class CastMotion {
  const CastMotion({
    required this.pose,
    required this.release,
    required this.recovery,
  });

  final CastPose pose;
  final double release;
  final double recovery;
}

// Light attack timing
const double startupSeconds = 0.18;
const double activeSeconds = 0.12;
const double recoverySeconds = 0.36;

const double lightDamage = 25;
const double lightKnockback = 3.5;

const List<Swing> lightCombo = [
  Swing(
    startup: startupSeconds,
    active: activeSeconds,
    recovery: recoverySeconds,
    damage: lightDamage,
    knockback: lightKnockback,
    lunge: 1.2,
  ),
  Swing(
    startup: 0.2,
    active: 0.1,
    recovery: 0.4,
    damage: 25,
    knockback: 4,
    lunge: 1.4,
  ),
  Swing(
    startup: 0.2,
    active: 0.12,
    recovery: 0.68,
    damage: 35,
    knockback: 7,
    lunge: 1.6,
    sweepsAround: true,
    shockwave: true,
  ),
];

// Heavy attack timing
const double heavyStartupSeconds = 0.5;
const double heavyActiveSeconds = 0.65;
const double heavyRecoverySeconds = 0.55;
const double heavyHitInterval = 0.30;
const double heavyDamage = 18;
const double heavyKnockback = 2.5;

const Swing heavySwing = Swing(
  startup: heavyStartupSeconds,
  active: heavyActiveSeconds,
  recovery: heavyRecoverySeconds,
  damage: heavyDamage,
  knockback: heavyKnockback,
  lunge: 1.0,
  hitInterval: heavyHitInterval,
  sweepsAround: true,
);

const double comboLinkSeconds = 0.08;
const double heavyRollCancelSeconds = heavyHitInterval;
const double moveCancelFraction = 0.55;

const double rollSeconds = 0.45;
const double iFrameStart = 0.05;
const double iFrameEnd = 0.32;
const double rollAttackOpensSeconds = iFrameEnd;
const double staggerSeconds = 0.35;

const double bufferWindow = 0.25;

final class Fighter {
  final phase = Machine<CombatPhase>(CombatPhase.idle);

  bool heavy = false;
  int combo = 0;
  CombatAction? queued;
  int swings = 0;
  int strikeHits = 0;

  Object? cast;
  CastMotion? castMotion;
  bool castReleased = false;

  Stance stance = Stance.free;

  double sinceHurt = double.infinity;
  double sinceCast = double.infinity;

  Swing get swing => heavy ? heavySwing : lightCombo[combo];

  bool get swinging =>
      phase.state == CombatPhase.startup ||
      phase.state == CombatPhase.active ||
      phase.state == CombatPhase.recovery;

  bool get iFramed =>
      phase.state == CombatPhase.rolling &&
      phase.elapsed >= iFrameStart &&
      phase.elapsed < iFrameEnd;

  bool get canAct => switch (phase.state) {
    CombatPhase.idle => true,
    CombatPhase.recovery => phase.elapsed >= comboLinkSeconds,
    CombatPhase.rolling => phase.elapsed >= rollAttackOpensSeconds,
    CombatPhase.casting => castRecovering,
    _ => false,
  };

  bool get castRecovering =>
      phase.state == CombatPhase.casting &&
      castReleased &&
      phase.elapsed >= castMotion!.release + castMotion!.recovery * 0.5;

  void beginSwing({required bool heavy, int combo = 0}) {
    queued = null;
    this.heavy = heavy;
    this.combo = combo;
    swings++;
    phase.go(CombatPhase.startup);
  }

  void beginCast(Object skill, CastMotion motion) {
    cast = skill;
    castMotion = motion;
    castReleased = false;
    swings++;
    phase.go(CombatPhase.casting);
  }
}

void fighterDriver(World world) {
  final buffer = world.buffer<CombatAction>();
  final axes = world.axes<MoveAxis>();
  final moving =
      axes.value(MoveAxis.x).abs() > 0.1 || axes.value(MoveAxis.y).abs() > 0.1;
  final leapt = world.events<CastLeap>().isNotEmpty;
  world.query<Fighter>().each((entity, fighter) {
    fighter.sinceHurt += world.dt;
    fighter.sinceCast += world.dt;
    if (leapt) fighter.sinceCast = 0;
    final phase = fighter.phase..tick(world.dt);
    final swing = fighter.swing;
    if (fighter.swinging) _queueAttack(buffer, fighter);
    switch (phase.state) {
      case CombatPhase.idle:
        if (!_startAttack(buffer, fighter, combo: 0) &&
            buffer.consume(CombatAction.roll)) {
          phase.go(CombatPhase.rolling);
        }
      case CombatPhase.startup:
        if (buffer.consume(CombatAction.roll)) {
          fighter.queued = null;
          phase.go(CombatPhase.rolling);
        } else if (phase.elapsed >= swing.startup) {
          phase.go(CombatPhase.active);
        }
      case CombatPhase.active:
        if (fighter.heavy &&
            phase.elapsed >= heavyRollCancelSeconds &&
            buffer.consume(CombatAction.roll)) {
          phase.go(CombatPhase.rolling);
        } else if (phase.elapsed >= swing.active) {
          phase.go(CombatPhase.recovery);
        }
      case CombatPhase.recovery:
        if (buffer.consume(CombatAction.roll)) {
          fighter.queued = null;
          phase.go(CombatPhase.rolling);
        } else if (phase.elapsed >= comboLinkSeconds &&
            _startQueued(fighter, combo: _nextCombo(fighter))) {
          break;
        } else if (phase.elapsed >= swing.recovery ||
            (moving && phase.elapsed >= swing.moveCancelSeconds)) {
          phase.go(CombatPhase.idle);
        }
      case CombatPhase.rolling:
        if (phase.elapsed >= rollAttackOpensSeconds &&
            _startAttack(buffer, fighter, combo: 0)) {
          break;
        }
        if (phase.elapsed >= rollSeconds) phase.go(CombatPhase.idle);
      case CombatPhase.staggered:
        if (phase.elapsed >= staggerSeconds) phase.go(CombatPhase.idle);
      case CombatPhase.casting:
        final motion = fighter.castMotion!;
        final end = motion.release + motion.recovery;
        if (fighter.castReleased && buffer.consume(CombatAction.roll)) {
          phase.go(CombatPhase.rolling);
        } else if (fighter.castRecovering &&
            _startAttack(buffer, fighter, combo: 0)) {
          break;
        } else if (phase.elapsed >= end || (moving && fighter.castRecovering)) {
          phase.go(CombatPhase.idle);
        }
    }
  });
}

void _queueAttack(InputBuffer<CombatAction> buffer, Fighter fighter) {
  if (buffer.consume(CombatAction.heavy)) {
    fighter.queued = CombatAction.heavy;
  } else if (buffer.consume(CombatAction.attack)) {
    fighter.queued ??= CombatAction.attack;
  }
}

bool _startQueued(Fighter fighter, {required int combo}) {
  final queued = fighter.queued;
  if (queued == null) return false;
  fighter.beginSwing(heavy: queued == CombatAction.heavy, combo: combo);
  return true;
}

int _nextCombo(Fighter fighter) =>
    fighter.heavy ? 0 : (fighter.combo + 1) % lightCombo.length;

bool _startAttack(
  InputBuffer<CombatAction> buffer,
  Fighter fighter, {
  required int combo,
}) {
  if (buffer.consume(CombatAction.heavy)) {
    fighter.beginSwing(heavy: true);
    return true;
  }
  if (buffer.consume(CombatAction.attack)) {
    fighter.beginSwing(heavy: false, combo: combo);
    return true;
  }
  return false;
}

void clearBufferOnStagger(World world) {
  final buffer = world.buffer<CombatAction>();
  world.query<Fighter>().each((entity, fighter) {
    if (fighter.phase.justEntered(CombatPhase.staggered)) buffer.clear();
  });
}
