import 'dart:math' as math;

import 'package:combat_sample/common/inputs.dart';
import 'package:combat_sample/features/player/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import 'support/fight_harness.dart' as fight;

int ticksFor(double seconds) => fight.ticksFor(seconds);

void installFighter(GameBuilder game) {
  game.world
    ..insert(InputBuffer<CombatAction>(window: bufferWindow))
    ..insert(ButtonInput<CombatAction>());
  game.addSystem(Schedules.fixedUpdate, fighterDriver, writes: {Fighter});
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

void press(TestGame game, CombatAction action) =>
    game.world.buffer<CombatAction>().record(action);

void pumpToRecovery(TestGame game, Fighter fighter) {
  while (fighter.phase.state != CombatPhase.recovery) {
    game.pumpFixed(steps: 1);
  }
}

void main() {
  test('a light attack swings on press while the button is still held', () {
    final (game, fighter) = boot();
    game.world.buttons<CombatAction>().setPressed(CombatAction.attack, true);
    press(game, CombatAction.attack);
    game.pumpFixed(steps: 1 + ticksFor(startupSeconds));
    expect(fighter.phase.state, CombatPhase.active);
    expect(fighter.heavy, isFalse);
  });

  test('attacks pressed in recovery chain the three-hit combo and wrap', () {
    final (game, fighter) = boot();
    press(game, CombatAction.attack);
    game.pumpFixed(steps: 1);
    final seen = <int>[fighter.combo];
    for (var i = 0; i < lightCombo.length; i++) {
      pumpToRecovery(game, fighter);
      game.pumpFixed(steps: ticksFor(comboLinkSeconds));
      press(game, CombatAction.attack);
      game.pumpFixed(steps: 1);
      expect(fighter.phase.state, CombatPhase.startup);
      seen.add(fighter.combo);
    }
    expect(seen, [0, 1, 2, 0]);
    expect(fighter.swings, 4);
  });

  test('a combo that lapses to idle restarts from the first swing', () {
    final (game, fighter) = boot();
    press(game, CombatAction.attack);
    game.pumpFixed(steps: 1);
    pumpToRecovery(game, fighter);
    game.pumpFixed(steps: ticksFor(recoverySeconds) + 1);
    expect(fighter.phase.state, CombatPhase.idle);
    press(game, CombatAction.attack);
    game.pumpFixed(steps: 1);
    expect(fighter.combo, 0);
  });

  test('a press early in a swing queues the next hit', () {
    final (game, fighter) = boot();
    press(game, CombatAction.attack);
    game.pumpFixed(steps: 1);
    press(game, CombatAction.attack);
    pumpToRecovery(game, fighter);
    game.pumpFixed(steps: ticksFor(comboLinkSeconds) + 1);
    expect(fighter.swings, 2);
    expect(fighter.combo, 1);
  });

  test('a roll drops the queued hit', () {
    final (game, fighter) = boot();
    press(game, CombatAction.attack);
    game.pumpFixed(steps: 1);
    press(game, CombatAction.attack);
    press(game, CombatAction.roll);
    game.pumpFixed(steps: ticksFor(rollSeconds) + 2);
    expect(fighter.phase.state, CombatPhase.idle);
    expect(fighter.swings, 1);
  });

  test('the heavy has its own input and a roll escapes its spin', () {
    final (game, fighter) = boot();
    press(game, CombatAction.heavy);
    game.pumpFixed(steps: 1);
    expect(fighter.heavy, isTrue);
    game.pumpFixed(steps: ticksFor(heavyStartupSeconds));
    expect(fighter.phase.state, CombatPhase.active);

    press(game, CombatAction.roll);
    game.pumpFixed(steps: 1);
    expect(fighter.phase.state, CombatPhase.active, reason: 'too early');
    game.pumpFixed(steps: ticksFor(heavyRollCancelSeconds));
    expect(fighter.phase.state, CombatPhase.active, reason: 'press expired');
    press(game, CombatAction.roll);
    game.pumpFixed(steps: 1);
    expect(fighter.phase.state, CombatPhase.rolling);
  });

  test('a roll cancels a startup, and an attack cancels a late roll', () {
    final (game, fighter) = boot();
    press(game, CombatAction.attack);
    game.pumpFixed(steps: 2);
    press(game, CombatAction.roll);
    game.pumpFixed(steps: 1);
    expect(fighter.phase.state, CombatPhase.rolling);

    game.pumpFixed(steps: ticksFor(rollAttackOpensSeconds) - 2);
    press(game, CombatAction.attack);
    game.pumpFixed(steps: 1);
    expect(fighter.phase.state, CombatPhase.rolling);
    game.pumpFixed(steps: 1);
    expect(fighter.phase.state, CombatPhase.startup);
    expect(fighter.combo, 0);
  });

  test('moving cancels the tail of a recovery, standing still does not', () {
    final (game, fighter) = boot();
    press(game, CombatAction.attack);
    game.pumpFixed(steps: 1);
    pumpToRecovery(game, fighter);
    game.pumpFixed(steps: ticksFor(lightCombo[0].moveCancelSeconds));
    expect(fighter.phase.state, CombatPhase.recovery);
    game.world.axes<MoveAxis>().setValue(MoveAxis.x, 1);
    game.pumpFixed(steps: 1);
    expect(fighter.phase.state, CombatPhase.idle);
  });

  test('a swing turns toward a nearby enemy off to the side', () {
    final game = fight.boot();
    final world = game.world;
    final enemy = fight.dummyInFront(game, distance: 3);
    final player = fight.playerOf(world);
    final at = world.get<SceneTransform>(player).translation;
    final facing = world.get<PlayerMotion>(player).facing;
    final offAxis = facing + 0.8;
    world
        .get<SceneTransform>(enemy)
        .translation
        .setValues(
          at.x + math.sin(offAxis) * 3,
          0,
          at.z + math.cos(offAxis) * 3,
        );

    press(game, CombatAction.attack);
    fight.pumpHolding(game, enemy, steps: 1 + ticksFor(startupSeconds));

    final enemyAt = world.get<SceneTransform>(enemy).translation;
    final playerAt = world.get<SceneTransform>(player).translation;
    final toEnemy = math.atan2(enemyAt.x - playerAt.x, enemyAt.z - playerAt.z);
    final turned = world.get<PlayerMotion>(player).facing;
    expect((turned - toEnemy).abs() % (2 * math.pi), lessThan(0.05));
    expect(
      math.sqrt(
        math.pow(enemyAt.x - playerAt.x, 2) +
            math.pow(enemyAt.z - playerAt.z, 2),
      ),
      lessThan(3),
      reason: 'the swing steps in',
    );
  });
}
