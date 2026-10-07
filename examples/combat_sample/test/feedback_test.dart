import 'package:combat_sample/features/feedback/feedback.dart';
import 'package:combat_sample/features/player/player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'support/fight_harness.dart';

final class DashLog {
  final List<Dashed> dashes = [];
}

void recordDashes(World world) {
  world.resource<DashLog>().dashes.addAll(world.events<Dashed>());
}

void installDashLog(GameBuilder game) {
  game
    ..world.insert(DashLog())
    ..addSystem(Schedules.fixedUpdate, recordDashes, reads: const {});
}

Entity sturdyDummy(TestGame game) {
  final enemy = dummyInFront(game, distance: 2);
  game.world.get<Health>(enemy).current = 999;
  return enemy;
}

void hit(
  TestGame game,
  Entity target, {
  HitWeight weight = HitWeight.light,
  double damage = 5,
}) {
  game.emit(
    HitLanded(
      target,
      damage,
      weight: weight,
      knockback: Vector3(1, 0, 0),
      stagger: false,
    ),
  );
  game.pumpFixed(steps: 2);
}

void main() {
  test('a landed strike flashes and recoils its target, then both settle', () {
    final game = boot();
    final world = game.world;
    final enemy = dummyInFront(game);
    landPlayerStrike(game, enemy);
    for (var step = 0; step < 4 && !world.has<HitFlash>(enemy); step++) {
      game.pumpFixed(steps: 1);
    }

    expect(world.has<HitFlash>(enemy), isTrue);
    expect(world.tryGet<Recoil>(enemy)?.direction.length, closeTo(1, 1e-6));
    expect(world.has<HitPause>(enemy), isTrue, reason: 'a short pause');
    game.pumpFixed(steps: ticksFor(lightHitPauseSeconds) + 1);
    expect(world.has<HitPause>(enemy), isFalse);

    game.pumpFixed(steps: ticksFor(hitFlashSeconds) + 1);
    expect(world.has<HitFlash>(enemy), isFalse);
    game.pump(dt: recoilSettleSeconds + 0.01);
    expect(world.has<Recoil>(enemy), isFalse);
  });

  test('finishers pause both poses briefly; gameplay never stops', () {
    final game = boot();
    final world = game.world;
    final enemy = sturdyDummy(game);
    final player = playerOf(world);

    hit(game, enemy, weight: HitWeight.finisher);
    expect(world.has<HitPause>(enemy), isTrue);
    expect(world.has<HitPause>(player), isTrue);
    expect(game.clock.timeScale, 1);

    game.pumpFixed(steps: ticksFor(hitPauseSeconds) + 1);
    expect(world.has<HitPause>(enemy), isFalse);
    expect(world.has<HitPause>(player), isFalse);
  });

  test('the combo counts connected hits and drops when the player is hit '
      'or the chain goes cold', () {
    final game = boot();
    final world = game.world;
    final meter = world.resource<ComboMeter>();
    final enemy = sturdyDummy(game);

    for (var i = 0; i < 3; i++) {
      hit(game, enemy);
    }
    expect(meter.hits, 3);

    hit(game, playerOf(world));
    expect(meter.hits, 0);
    expect(meter.best, 3);

    hit(game, enemy);
    game.pumpFixed(steps: ticksFor(comboTimeoutSeconds) + 2);
    expect(meter.hits, 0);
  });

  test('damage over time counts neither toward the combo nor a reaction', () {
    final game = boot();
    final world = game.world;
    final enemy = sturdyDummy(game);
    game.emit(HitLanded(enemy, 3, stagger: false, impact: false));
    game.pumpFixed(steps: 2);
    expect(world.resource<ComboMeter>().hits, 0);
    expect(world.has<HitFlash>(enemy), isFalse);
  });

  test('a roll announces exactly one dash along its committed direction', () {
    final game = boot(extra: [installDashLog]);
    final world = game.world;
    world.buffer<CombatAction>().record(CombatAction.roll);
    game.pumpFixed(steps: ticksFor(rollSeconds) + 2);

    final dashes = world.resource<DashLog>().dashes;
    expect(dashes, hasLength(1));
    final motion = world.get<PlayerMotion>(playerOf(world));
    expect(dashes.single.heading.dot(motion.rollDirection), closeTo(1, 1e-6));
  });
}
