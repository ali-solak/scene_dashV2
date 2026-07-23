/// The framework's `combat_machine_reference_test`, lifted to run against
/// the game's real `player/combat/combat.dart`. Scenario systems and the
/// scoreboard stay test-side; tick counts come from [ticksFor], never
/// assumed.
library;

import 'package:combat_sample/player/combat/combat.dart';
import 'package:combat_sample/rules/rules.dart' show applyDamage;
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

/// The tick count on which a phase entered at tick zero first satisfies
/// `elapsed >= seconds`, replaying the machine's accumulation order.
int ticksFor(double seconds) {
  var t = 0.0;
  var n = 0;
  while (t < seconds) {
    t += combatFixedDt;
    n++;
  }
  return n;
}

/// The pump count a freeze of [freeze] wall-seconds stalls, mirroring
/// GameClock's arithmetic (scale read before the wall dt is served).
int frozenPumpsFor(double freeze) {
  var remaining = freeze;
  var pumps = 0;
  while (remaining > 0) {
    pumps++;
    remaining -= combatFixedDt;
  }
  return pumps;
}

/// Pumps until exactly [ticks] more fixed steps have run: machine time,
/// transparent to any hitstop frames interleaved by the clock.
void pumpMachineTicks(TestGame game, CombatLog log, int ticks) {
  final target = log.steps + ticks;
  while (log.steps < target) {
    game.pumpFixed(steps: 1);
  }
}

/// Scoreboard + hitbox window bookkeeping; test instrumentation over the
/// game systems' edges.
final class CombatLog {
  int steps = 0;
  int swings = 0;
  bool hitboxOpen = false;
  int hitboxTicks = 0;
  int blocked = 0;
  int landed = 0;
  final List<CombatPhase> trace = <CombatPhase>[];
}

/// Scores incoming hits against the i-frame window *before*
/// [applyDamage] staggers the fighter (its own event reader sees the
/// same events).
void scoreIncomingHits(World world) {
  final log = world.resource<CombatLog>();
  for (final hit in world.events<HitLanded>()) {
    final fighter = world.tryGet<Fighter>(hit.target);
    if (fighter == null) continue;
    if (fighter.iFramed) {
      log.blocked++;
    } else {
      log.landed++;
    }
  }
}

/// The hitbox window IS the edge pair: opens on `justEntered(active)`,
/// closes on `justExited(active)`.
void hitboxSystem(World world) {
  final log = world.resource<CombatLog>();
  world.query<Fighter>().each((entity, fighter) {
    if (fighter.phase.justEntered(CombatPhase.active)) {
      log.hitboxOpen = true;
      log.swings++;
    }
    if (fighter.phase.justExited(CombatPhase.active)) {
      log.hitboxOpen = false;
    }
  });
}

/// Counts steps, open-hitbox ticks, and records the phase trace.
void recordTrace(World world) {
  final log = world.resource<CombatLog>();
  log.steps++;
  if (log.hitboxOpen) log.hitboxTicks++;
  world.query<Fighter>().each((entity, fighter) {
    log.trace.add(fighter.phase.state);
  });
}

void installFighter(GameBuilder game) {
  game.world
    ..insert(InputBuffer<CombatAction>(window: bufferWindow))
    ..insert(ButtonInput<CombatAction>())
    ..insert(CombatLog());
  game
    ..registerComponent<Fighter>()
    ..addSystem(Schedules.fixedUpdate, fighterDriver, writes: {Fighter})
    ..addSystem(
      Schedules.fixedUpdate,
      scoreIncomingHits,
      reads: {Fighter},
      after: [fighterDriver],
    )
    ..addSystem(
      Schedules.fixedUpdate,
      applyDamage,
      writes: {Fighter},
      after: [scoreIncomingHits],
    )
    ..addSystem(
      Schedules.fixedUpdate,
      clearBufferOnStagger,
      reads: {Fighter},
      after: [applyDamage],
    )
    ..addSystem(
      Schedules.fixedUpdate,
      hitboxSystem,
      reads: {Fighter},
      after: [clearBufferOnStagger],
    )
    ..addSystem(
      Schedules.fixedUpdate,
      recordTrace,
      reads: {Fighter},
      after: [hitboxSystem],
    );
}

(TestGame, Entity, CombatLog) boot() {
  final game = TestGame.headless(
    fixedDt: combatFixedDt,
    features: [installFighter],
  );
  final fighter = game.world.spawn([Fighter()]);
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
    expect(
      log.hitboxTicks,
      activeTicks,
      reason: 'open for exactly the active window',
    );
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
    game2.emit(HitLanded(fighter2, 10));
    game2.pumpFixed(steps: 1); // this tick crosses iFrameStart: blocked
    expect(log2.blocked, 1, reason: 'window opens exactly at iFrameStart');
    expect(log2.landed, 0);

    // At the closing boundary the same hit lands.
    game.pumpFixed(steps: ticksFor(iFrameEnd) - 1);
    game.emit(HitLanded(fighter, 10));
    game.pumpFixed(steps: 1); // this tick crosses iFrameEnd: window shut
    expect(log.landed, 1, reason: 'window shuts exactly at iFrameEnd');
    expect(log.blocked, 0);
  });

  test(
    'a roll buffered during recovery cancels the tail and fires at once',
    () {
      final (game, _, log) = boot();
      game.world.buffer<CombatAction>().record(CombatAction.attack);
      game.pumpFixed(steps: 1 + startupTicks + activeTicks); // recovery starts
      expect(log.trace.last, CombatPhase.recovery);

      // Recovery cancel (a sample addition): committing to a swing is never a
      // trap you cannot roll out of, so a roll buffered in the follow-through
      // does NOT wait for idle; it fires on the very next tick.
      game.world.buffer<CombatAction>().record(CombatAction.roll);
      game.pumpFixed(steps: 1);
      expect(
        log.trace.last,
        CombatPhase.rolling,
        reason: 'the buffered roll cancels recovery immediately',
      );
    },
  );

  test('justEntered(staggered) clears the buffer: intent recorded before '
      'the hit never fires out of it', () {
    final (game, fighter, log) = boot();
    game.world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: 1); // swing starts (startup: not i-framed)
    game.world.buffer<CombatAction>().record(CombatAction.roll); // buffered
    game.emit(HitLanded(fighter, 10));
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
    expect(
      log.trace.last,
      CombatPhase.idle,
      reason: 'the cleared roll did not fire after the stagger',
    );
  });

  test('hitstop stalls elapsed and shifts every subsequent boundary by '
      'exactly the frozen ticks', () {
    final (game, fighter, log) = boot();
    game.world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: 1); // startup entered
    game.emit(HitLanded(fighter, 10));
    game.pumpFixed(steps: 1); // lands: staggered (the sample no longer freezes)

    // Hits stopped freezing the clock (the hitstop read as lag), but the
    // freeze is a framework mechanic in its own right: drive it directly
    // and prove frozen frames still run no fixed step.
    const freezeSeconds = 0.05;
    game.world.clock.freezeFor(freezeSeconds);
    final stepsAtFreeze = log.steps;

    // Every frozen frame renders but runs no fixed step: the machine
    // stalls for exactly the pump count the clock's arithmetic dictates.
    final frozen = frozenPumpsFor(freezeSeconds);
    game.pumpFixed(steps: frozen);
    expect(
      log.steps,
      stepsAtFreeze,
      reason: 'frozen frames run no fixed steps: the machine stalls',
    );
    game.pumpFixed(steps: 1);
    expect(
      log.steps,
      stepsAtFreeze + 1,
      reason: 'resumes on the very next pump: shift == frozen frames',
    );

    // The stagger still serves its full duration in machine ticks: every
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
      game.emit(HitLanded(fighter, 10));
      game.pumpFixed(steps: 3);
      game.emit(HitLanded(fighter, 10));
      game.pumpFixed(steps: 60);
      return '${log.trace.join(',')}|${log.blocked}|${log.landed}|'
          '${log.swings}|${log.hitboxTicks}';
    }

    expect(run(), run());
  });
}
