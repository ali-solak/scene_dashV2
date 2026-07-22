/// The heavy attack (task 8): one button, hold-to-commit, frame-exact.
library;

import 'package:combat_sample/player/combat/combat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

int ticksFor(double seconds) {
  var t = 0.0;
  var n = 0;
  while (t < seconds) {
    t += combatFixedDt;
    n++;
  }
  return n;
}

void installFighter(GameBuilder game) {
  game.world
    ..insert(InputBuffer<CombatAction>(window: bufferWindow))
    ..insert(ButtonInput<CombatAction>());
  game
    ..registerComponent<Fighter>()
    ..addSystem(Schedules.frameStart, ageCombatBuffer, reads: const {})
    ..addSystem(Schedules.fixedUpdate, fighterDriver, writes: {Fighter});
}

(TestGame, Fighter) boot() {
  final game = TestGame.headless(
    fixedDt: combatFixedDt,
    features: [installFighter],
  );
  final entity = game.world.spawn([Fighter()]);
  game.start();
  return (game, game.world.get<Fighter>(entity));
}

void main() {
  final startupTicks = ticksFor(startupSeconds);
  final thresholdTicks = ticksFor(heavyThresholdSeconds);
  final heavyStartupTicks = ticksFor(heavyStartupSeconds);

  test('a tap stays light: active at the reference startup boundary', () {
    final (game, fighter) = boot();
    game.world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: 1); // startup entered
    game.pumpFixed(steps: startupTicks - 1);
    expect(fighter.phase.state, CombatPhase.startup);
    game.pumpFixed(steps: 1);
    expect(fighter.phase.state, CombatPhase.active);
    expect(fighter.heavy, isFalse);
  });

  test('holding past the threshold promotes on the exact tick and commits '
      'to the heavy startup boundary', () {
    final (game, fighter) = boot();
    final buttons = game.world.buttons<CombatAction>();
    buttons.setPressed(CombatAction.attack, true);
    game.world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: 1); // startup entered

    game.pumpFixed(steps: thresholdTicks - 1);
    expect(fighter.heavy, isFalse, reason: 'one tick before the threshold');
    expect(
      fighter.phase.state,
      CombatPhase.startup,
      reason: 'the hold delays the light boundary',
    );
    game.pumpFixed(steps: 1);
    expect(fighter.heavy, isTrue, reason: 'promoted exactly at threshold');

    // Committed: releasing after promotion changes nothing.
    buttons.setPressed(CombatAction.attack, false);
    game.pumpFixed(steps: heavyStartupTicks - thresholdTicks - 1);
    expect(fighter.phase.state, CombatPhase.startup);
    game.pumpFixed(steps: 1);
    expect(
      fighter.phase.state,
      CombatPhase.active,
      reason: 'heavy goes active at its own startup boundary',
    );
    expect(fighter.heavy, isTrue);
  });

  test('releasing between the light boundary and the threshold fires the '
      'light immediately', () {
    final (game, fighter) = boot();
    final buttons = game.world.buttons<CombatAction>();
    buttons.setPressed(CombatAction.attack, true);
    game.world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: 1);

    // Hold through the light boundary but not to the threshold.
    game.pumpFixed(steps: startupTicks + 2);
    expect(
      fighter.phase.state,
      CombatPhase.startup,
      reason: 'still winding up while held',
    );
    expect(fighter.heavy, isFalse);

    buttons.setPressed(CombatAction.attack, false);
    game.pumpFixed(steps: 1);
    expect(
      fighter.phase.state,
      CombatPhase.active,
      reason: 'release past the light boundary swings at once',
    );
    expect(fighter.heavy, isFalse);
  });

  test('the heavy flag resets for the next swing', () {
    final (game, fighter) = boot();
    final buttons = game.world.buttons<CombatAction>();
    buttons.setPressed(CombatAction.attack, true);
    game.world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: 1 + heavyStartupTicks + 1);
    expect(fighter.heavy, isTrue);
    buttons.setPressed(CombatAction.attack, false);

    // Ride out the spin's long active sweep + recovery back to idle, then
    // tap.
    game.pumpFixed(
      steps: ticksFor(heavyActiveSeconds) + ticksFor(heavyRecoverySeconds) + 2,
    );
    expect(fighter.phase.state, CombatPhase.idle);
    game.world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: 1);
    expect(fighter.phase.state, CombatPhase.startup);
    expect(fighter.heavy, isFalse, reason: 'a fresh swing starts light');
  });
}
