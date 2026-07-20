/// The game layer, headless: waves field, clear and escalate; kills pay
/// points; giant waves field exactly one giant that swells on the
/// transform clock, hits harder and launches the player off the ground.
library;

import 'dart:math' as math;

import 'package:combat_sample/enemies/enemies.dart';
import 'package:combat_sample/game/actors.dart';
import 'package:combat_sample/game/score.dart';
import 'package:combat_sample/player/player.dart';
import 'package:combat_sample/waves/waves.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import 'support/fight_harness.dart';

int enemyCount(World world) =>
    world.entitiesWith(require: const [Enemy]).count();

/// Wipes the field the blunt way — these tests are about the director,
/// not about how a barbarian dies.
void clearField(TestGame game) {
  game.world.entitiesWith(require: const [Enemy]).each(game.world.despawn);
  game.pumpFixed(steps: 1);
}

/// Winds the director forward to just before [wave] fields.
void armWave(TestGame game, int wave) {
  clearField(game);
  game.world.resource<WaveState>()
    ..wave = wave - 1
    ..engaged = false
    ..intermission = 0;
  game.pumpFixed(steps: 1);
}

/// The one giant on the field.
(Entity, Brawler) giantOf(World world) {
  final found = <(Entity, Brawler)>[];
  world.query<Brawler>(require: const [Enemy]).each((entity, brawler) {
    if (brawler.giant) found.add((entity, brawler));
  });
  expect(found.length, 1, reason: 'a giant wave fields exactly one giant');
  return found.first;
}

void main() {
  test('the run opens on wave 1 with its pack fielded', () {
    final game = boot();
    final waves = game.world.resource<WaveState>();
    expect(waves.wave, 1);
    expect(waves.engaged, isTrue);
    expect(enemyCount(game.world), enemiesForWave(1));
  });

  test('clearing a wave takes a breather, then fields a bigger one', () {
    final game = boot();
    final world = game.world;
    final waves = world.resource<WaveState>();

    clearField(game);
    expect(waves.engaged, isFalse, reason: 'the wave is down');
    expect(waves.intermission, closeTo(waveIntermissionSeconds, 1e-6));
    expect(enemyCount(world), 0, reason: 'nobody walks in during the breather');

    // The breather runs down without fielding anything.
    game.pumpFixed(steps: ticksFor(waveIntermissionSeconds) - 2);
    expect(waves.wave, 1);
    expect(enemyCount(world), 0);

    // Then wave 2 walks in, tougher than wave 1.
    game.pumpFixed(steps: 4);
    expect(waves.wave, 2);
    expect(enemyCount(world), enemiesForWave(2));
    world.query<Health>(require: const [Enemy]).each((entity, health) {
      expect(health.max, closeTo(healthForWave(2), 1e-6));
      expect(health.max, greaterThan(enemyMaxHealth));
    });
  });

  test('barbarians walk in from outside the fighting circle', () {
    final game = boot();
    game.world.query<SceneTransform>(require: const [Enemy]).each((entity, t) {
      final distance = math.sqrt(
        t.translation.x * t.translation.x + t.translation.z * t.translation.z,
      );
      expect(distance, closeTo(waveSpawnRadius, 1e-6));
      expect(distance, greaterThan(engageRange), reason: 'they close in');
    });
  });

  test('a kill pays points into the bank', () {
    final game = boot();
    final world = game.world;
    final score = world.resource<Score>();
    expect(score.points, 0);

    final enemy = world.entitiesWith(require: const [Enemy]).firstOrNull!;
    world.get<Health>(enemy).current = 10; // the next strike kills
    landPlayerStrike(game, enemy);

    expect(score.kills, 1);
    expect(score.points, enemyPoints);
    expect(score.earned, enemyPoints, reason: 'earned is the run total');
  });

  test('a giant wave fields one giant: tougher, stronger, and frozen while '
      'it swells', () {
    final game = boot();
    final world = game.world;
    armWave(game, firstGiantWave);
    expect(world.resource<WaveState>().wave, firstGiantWave);

    final (entity, brawler) = giantOf(world);
    expect(
      world.get<Health>(entity).max,
      closeTo(healthForWave(firstGiantWave) * giantHealthFactor, 1e-6),
    );
    expect(
      brawler.power,
      closeTo(powerForWave(firstGiantWave) * giantPower, 1e-6),
    );

    // It arrives mid-transform and holds still while the clip plays: no
    // walking in, no swinging, until it has finished growing.
    final home = world.get<SceneTransform>(entity).translation.clone();
    expect(world.expiryOf<Transforming>(entity), isNotNull);
    game.pumpFixed(steps: ticksFor(giantTransformSeconds) - 4);
    expect(world.get<SceneTransform>(entity).translation, home);
    expect(brawler.phase.state, isNot(BrawlPhase.swing));

    // Clock done: it drops the tag and joins the fight.
    game.pumpFixed(steps: 8);
    expect(world.expiryOf<Transforming>(entity), isNull);
    game.pumpFixed(steps: 20);
    expect(
      world.get<SceneTransform>(entity).translation,
      isNot(home),
      reason: 'it walks in once it has grown',
    );
  });

  test('a giant blow launches the player off the ground', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    clearField(game);

    // One grown giant, in the player's face, so its swing connects.
    final transform = world.get<SceneTransform>(player).translation;
    world.spawn(
      enemyBundle(
        transform.x,
        transform.z + 2,
        index: 0,
        power: giantPower,
        giant: true,
      ),
    );
    game.pumpFixed(steps: 1);

    final knockback = world.get<Knockback>(player);
    var launched = false;
    for (var tick = 0; tick < 600 && !launched; tick++) {
      game.pumpFixed(steps: 1);
      if (knockback.airborne) launched = true;
    }
    expect(launched, isTrue, reason: 'the giant sends the player flying');

    // And what goes up comes down: the arc lands the player back on the
    // floor rather than leaving them hanging.
    game.pumpFixed(steps: 300);
    expect(knockback.airborne, isFalse);
    expect(world.get<SceneTransform>(player).translation.y, 0);
  });
}
