/// The combat reference: a complete souls-style fighter built on
/// [Machine] alone — tests only, no game code. This suite is
/// simultaneously the primitive's stress proof and the seed artifact of a
/// future combat game; it is written to be lifted.
///
/// Boundaries are asserted frame-exact. A 1/60 step is not an exact
/// binary float, so expected tick counts are *computed from the
/// constants* by [ticksFor], which replays the machine's own
/// accumulation — never assumed from real division.
library;

import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

enum CombatPhase { idle, startup, active, recovery, rolling, staggered }

enum CombatAction { attack, roll }

const double fixedDt = 1 / 60;
const double startupSeconds = 0.25;
const double activeSeconds = 0.15;
const double recoverySeconds = 0.30;
const double rollSeconds = 0.50;
const double iFrameStart = 0.05;
const double iFrameEnd = 0.35;
const double staggerSeconds = 0.40;
const double bufferWindow = 0.40;
const double hitstopSeconds = 4 * fixedDt;

/// The tick count on which a phase entered at tick zero first satisfies
/// `elapsed >= seconds`, replaying the machine's accumulation order.
int ticksFor(double seconds) {
  var t = 0.0;
  var n = 0;
  while (t < seconds) {
    t += fixedDt;
    n++;
  }
  return n;
}

/// The pump count a freeze of [freeze] wall-seconds stalls, mirroring
/// [GameClock]: the scale is read (frozen while remaining > 0) before the
/// frame's wall dt is served, so fp residue in the last subtraction is
/// reproduced, not assumed away.
int frozenPumpsFor(double freeze) {
  var remaining = freeze;
  var pumps = 0;
  while (remaining > 0) {
    pumps++;
    remaining -= fixedDt;
  }
  return pumps;
}

/// Pumps until exactly [ticks] more fixed steps have run — machine time,
/// transparent to any hitstop frames interleaved by the clock.
void pumpMachineTicks(TestGame game, CombatLog log, int ticks) {
  final target = log.steps + ticks;
  while (log.steps < target) {
    game.pumpFixed(steps: 1);
  }
}

final class AttackState {
  final phase = Machine<CombatPhase>(CombatPhase.idle);

  bool get iFramed =>
      phase.state == CombatPhase.rolling &&
      phase.elapsed >= iFrameStart &&
      phase.elapsed < iFrameEnd;
}

/// An incoming enemy hit against [target], sent by the test scenario.
final class IncomingHit {
  final Entity target;
  const IncomingHit(this.target);
}

/// Scoreboard + hitbox window bookkeeping, written by the systems below.
final class CombatLog {
  int steps = 0;
  int swings = 0;
  bool hitboxOpen = false;
  int hitboxTicks = 0;
  int blocked = 0;
  int landed = 0;
  final List<CombatPhase> trace = <CombatPhase>[];
}

/// The owner: ticks the machine, then transitions on time and buffered
/// intent. Compute stays on the component; effects live in the systems
/// below, acting on the edges this leaves raised.
void fighterDriver(World world) {
  final buffer = world.buffer<CombatAction>();
  world.query<AttackState>().each((entity, attack) {
    final phase = attack.phase..tick(world.dt);
    switch (phase.state) {
      case CombatPhase.idle:
        if (buffer.consume(CombatAction.attack)) {
          phase.go(CombatPhase.startup);
        } else if (buffer.consume(CombatAction.roll)) {
          phase.go(CombatPhase.rolling);
        }
      case CombatPhase.startup:
        if (phase.elapsed >= startupSeconds) phase.go(CombatPhase.active);
      case CombatPhase.active:
        if (phase.elapsed >= activeSeconds) phase.go(CombatPhase.recovery);
      case CombatPhase.recovery:
        if (phase.elapsed >= recoverySeconds) phase.go(CombatPhase.idle);
      case CombatPhase.rolling:
        if (phase.elapsed >= rollSeconds) phase.go(CombatPhase.idle);
      case CombatPhase.staggered:
        if (phase.elapsed >= staggerSeconds) phase.go(CombatPhase.idle);
    }
  });
}

/// Incoming hits resolve against the i-frame window; a landed hit
/// staggers the fighter and freezes the clock (hitstop).
void applyIncomingHits(World world) {
  final log = world.resource<CombatLog>();
  for (final hit in world.events<IncomingHit>()) {
    final attack = world.tryGet<AttackState>(hit.target);
    if (attack == null) continue;
    if (attack.iFramed) {
      log.blocked++;
    } else {
      log.landed++;
      attack.phase.go(CombatPhase.staggered);
      world.clock.freezeFor(hitstopSeconds);
    }
  }
}

/// Getting staggered wipes buffered intent — a stale press must never
/// fire out of a hit. Reads the entry edge the same frame it was raised.
void clearBufferOnStagger(World world) {
  final buffer = world.buffer<CombatAction>();
  world.query<AttackState>().each((entity, attack) {
    if (attack.phase.justEntered(CombatPhase.staggered)) buffer.clear();
  });
}

/// The hitbox window IS the edge pair: opens on `justEntered(active)`,
/// closes on `justExited(active)`; one swing lands exactly once — on the
/// open, with no per-swing dedup set needed.
void hitboxSystem(World world) {
  final log = world.resource<CombatLog>();
  world.query<AttackState>().each((entity, attack) {
    if (attack.phase.justEntered(CombatPhase.active)) {
      log.hitboxOpen = true;
      log.swings++;
    }
    if (attack.phase.justExited(CombatPhase.active)) {
      log.hitboxOpen = false;
    }
  });
}

/// Counts steps, open-hitbox ticks, and records the phase trace.
void recordTrace(World world) {
  final log = world.resource<CombatLog>();
  log.steps++;
  if (log.hitboxOpen) log.hitboxTicks++;
  world.query<AttackState>().each((entity, attack) {
    log.trace.add(attack.phase.state);
  });
}

/// The buffer ages on wall time, so hitstop cannot extend it.
void ageBuffer(World world) {
  world
      .resource<InputBuffer<CombatAction>>()
      .advance(world.resource<FrameTime>().unscaledDelta);
}

void installFighter(GameBuilder game) {
  game.world
    ..insert(InputBuffer<CombatAction>(window: bufferWindow))
    ..insert(CombatLog());
  game
    ..addSystem(Schedules.frameStart, ageBuffer, reads: const {})
    ..addSystem(Schedules.fixedUpdate, fighterDriver, writes: {AttackState})
    ..addSystem(Schedules.fixedUpdate, applyIncomingHits,
        writes: {AttackState}, after: [fighterDriver])
    ..addSystem(Schedules.fixedUpdate, clearBufferOnStagger,
        reads: {AttackState}, after: [applyIncomingHits])
    ..addSystem(Schedules.fixedUpdate, hitboxSystem,
        reads: {AttackState}, after: [clearBufferOnStagger])
    ..addSystem(Schedules.fixedUpdate, recordTrace,
        reads: {AttackState}, after: [hitboxSystem]);
}

(TestGame, Entity, CombatLog) boot() {
  final game = TestGame.headless(fixedDt: fixedDt, features: [installFighter]);
  final fighter = game.world.spawn([AttackState()]);
  game.start();
  return (game, fighter, game.world.resource<CombatLog>());
}

void main() {
  final startupTicks = ticksFor(startupSeconds);
  final activeTicks = ticksFor(activeSeconds);
  final recoveryTicks = ticksFor(recoverySeconds);

  test('the phase walk startup -> active -> recovery -> idle lands on the '
      'exact ticks computed from the constants', () {
    final (game, _, log) = boot();
    game.world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: 1); // consumed: startup entered this tick
    expect(log.trace.last, CombatPhase.startup);

    game.pumpFixed(steps: startupTicks - 1);
    expect(log.trace.last, CombatPhase.startup, reason: 'last startup tick');
    game.pumpFixed(steps: 1);
    expect(log.trace.last, CombatPhase.active, reason: 'exact boundary');

    game.pumpFixed(steps: activeTicks - 1);
    expect(log.trace.last, CombatPhase.active);
    game.pumpFixed(steps: 1);
    expect(log.trace.last, CombatPhase.recovery);

    game.pumpFixed(steps: recoveryTicks - 1);
    expect(log.trace.last, CombatPhase.recovery);
    game.pumpFixed(steps: 1);
    expect(log.trace.last, CombatPhase.idle);
  });

  test('the hitbox window is exactly the active phase: open on '
      'justEntered, closed on justExited, one swing hits once', () {
    final (game, _, log) = boot();
    game.world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: 1 + startupTicks + activeTicks + recoveryTicks + 5);
    expect(log.swings, 1, reason: 'one swing, one land');
    expect(log.hitboxTicks, activeTicks,
        reason: 'open for exactly the active window');
    expect(log.hitboxOpen, isFalse);

    game.world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: 1 + startupTicks + activeTicks + recoveryTicks + 5);
    expect(log.swings, 2, reason: 'a second swing lands exactly once more');
    expect(log.hitboxTicks, 2 * activeTicks);
  });

  test('i-frames block and lapse on the exact boundary ticks', () {
    final (game, fighter, log) = boot();
    game.world.buffer<CombatAction>().record(CombatAction.roll);
    game.pumpFixed(steps: 1); // rolling entered, elapsed 0

    // One tick before the window opens: a hit lands (and staggers).
    final (game2, fighter2, log2) = boot();
    game2.world.buffer<CombatAction>().record(CombatAction.roll);
    game2.pumpFixed(steps: 1);
    game2.pumpFixed(steps: ticksFor(iFrameStart) - 1);
    game2.emit(IncomingHit(fighter2));
    game2.pumpFixed(steps: 1); // this tick crosses iFrameStart: blocked
    expect(log2.blocked, 1, reason: 'window opens exactly at iFrameStart');
    expect(log2.landed, 0);

    // At the closing boundary the same hit lands.
    game.pumpFixed(steps: ticksFor(iFrameEnd) - 1);
    game.emit(IncomingHit(fighter));
    game.pumpFixed(steps: 1); // this tick crosses iFrameEnd: window shut
    expect(log.landed, 1, reason: 'window shuts exactly at iFrameEnd');
    expect(log.blocked, 0);
  });

  test('a roll buffered during recovery fires on the first idle tick', () {
    final (game, _, log) = boot();
    game.world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: 1 + startupTicks + activeTicks); // recovery starts
    expect(log.trace.last, CombatPhase.recovery);

    game.world.buffer<CombatAction>().record(CombatAction.roll);
    game.pumpFixed(steps: recoveryTicks);
    expect(log.trace.last, CombatPhase.idle, reason: 'recovery just ended');
    game.pumpFixed(steps: 1);
    expect(log.trace.last, CombatPhase.rolling,
        reason: 'the buffered roll fires on the first idle tick');
  });

  test('justEntered(staggered) clears the buffer: intent recorded before '
      'the hit never fires out of it', () {
    final (game, fighter, log) = boot();
    game.world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: 1); // swing starts (startup: not i-framed)
    game.world.buffer<CombatAction>().record(CombatAction.roll); // buffered
    game.emit(IncomingHit(fighter));
    game.pumpFixed(steps: 1); // lands: staggered, buffer cleared, hitstop
    expect(log.landed, 1);
    expect(log.trace.last, CombatPhase.staggered);

    // Stagger runs on machine time; counting machine ticks keeps the
    // boundary exact across the hitstop frames the landing started.
    pumpMachineTicks(game, log, ticksFor(staggerSeconds) - 1);
    expect(log.trace.last, CombatPhase.staggered, reason: 'last stagger tick');
    pumpMachineTicks(game, log, 1);
    expect(log.trace.last, CombatPhase.idle);
    pumpMachineTicks(game, log, 5);
    expect(log.trace.last, CombatPhase.idle,
        reason: 'the cleared roll did not fire after the stagger');
  });

  test('hitstop stalls elapsed and shifts every subsequent boundary by '
      'exactly the frozen ticks', () {
    final (game, fighter, log) = boot();
    game.world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: 1); // startup entered
    game.emit(IncomingHit(fighter));
    game.pumpFixed(steps: 1); // lands: staggered + freezeFor(hitstop)
    final stepsAtFreeze = log.steps;

    // Every frozen frame renders but runs no fixed step: the machine
    // stalls for exactly the pump count the clock's arithmetic dictates.
    final frozen = frozenPumpsFor(hitstopSeconds);
    game.pumpFixed(steps: frozen);
    expect(log.steps, stepsAtFreeze,
        reason: 'frozen frames run no fixed steps: the machine stalls');
    game.pumpFixed(steps: 1);
    expect(log.steps, stepsAtFreeze + 1,
        reason: 'resumes on the very next pump: shift == frozen frames');

    // The stagger still serves its full duration in machine ticks — every
    // boundary after the freeze lands the frozen count later in wall
    // frames, and exactly on time in machine time.
    game.pumpFixed(steps: ticksFor(staggerSeconds) - 2); // one already ran
    expect(log.trace.last, CombatPhase.staggered, reason: 'last stagger tick');
    game.pumpFixed(steps: 1);
    expect(log.trace.last, CombatPhase.idle);
  });

  test('determinism: the same inputs twice give identical phase traces', () {
    String run() {
      final (game, fighter, log) = boot();
      final buffer = game.world.buffer<CombatAction>();
      buffer.record(CombatAction.attack);
      game.pumpFixed(steps: 9);
      buffer.record(CombatAction.roll);
      game.pumpFixed(steps: 40);
      game.emit(IncomingHit(fighter));
      game.pumpFixed(steps: 3);
      game.emit(IncomingHit(fighter));
      game.pumpFixed(steps: 60);
      return '${log.trace.join(',')}|${log.blocked}|${log.landed}|'
          '${log.swings}|${log.hitboxTicks}';
    }

    expect(run(), run());
  });
}
