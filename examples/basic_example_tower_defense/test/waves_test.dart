import 'package:basic_example_tower_defense/common/game_state.dart';
import 'package:basic_example_tower_defense/features/creeps/creeps.dart';
import 'package:basic_example_tower_defense/features/creeps/data/config.dart';
import 'package:basic_example_tower_defense/features/damage/damage.dart';
import 'package:basic_example_tower_defense/features/rules/rules.dart';
import 'package:basic_example_tower_defense/features/towers/towers.dart';
import 'package:basic_example_tower_defense/features/waves/data/config.dart';
import 'package:basic_example_tower_defense/features/waves/waves.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

void main() {
  TestGame boot() => TestGame.headless(
    features: [
      installDamage,
      installCreeps,
      installWaves,
      installTowers,
      installRules,
    ],
  )..start();

  int stepsFor(double seconds) => (seconds * 60).ceil() + 1;

  int creepCount(TestGame game) =>
      game.world.query<SceneTransform>(require: const [Creep]).count();

  void finishWave(TestGame game) {
    game.world.resource<Wave>().left = 0;
    game.world
        .query<SceneTransform>(require: const [Creep])
        .each((creep, _) => game.world.despawn(creep));
    game.pumpFixed(steps: 2);
  }

  test('the first wave starts after the breather', () {
    final game = boot();

    game.pumpFixed(steps: stepsFor(breatherSeconds - 0.5));
    expect(game.world.resource<Wave>().number, 0);

    game.pumpFixed(steps: stepsFor(0.5));
    final wave = game.world.resource<Wave>();
    expect(wave.number, 1);
    expect(wave.phase.state, WavePhase.attacking);
  });

  test('a wave sends exactly its size in creeps', () {
    final game = boot();

    game.pumpFixed(
      steps: stepsFor(breatherSeconds + spawnGapSeconds * (waveSize(1) + 2)),
    );

    expect(creepCount(game), waveSize(1));
    expect(game.world.resource<Wave>().left, 0);
  });

  test('clearing a wave pays its bonus and opens the next breather', () {
    final game = boot();
    game.pumpFixed(steps: stepsFor(breatherSeconds));
    final goldBefore = game.world.resource<Gold>().value;

    finishWave(game);

    final wave = game.world.resource<Wave>();
    expect(wave.phase.state, WavePhase.breather);
    expect(game.world.resource<Gold>().value, goldBefore + waveBonus(1));
  });

  test('the second wave is tougher', () {
    final game = boot();
    game.pumpFixed(steps: stepsFor(breatherSeconds));
    finishWave(game);

    game.pumpFixed(steps: stepsFor(breatherSeconds + spawnGapSeconds));

    final (_, health) = game.world
        .query<Health>(require: const [Creep])
        .records
        .first;
    expect(game.world.resource<Wave>().number, 2);
    expect(health.max, runnerHealth * waveHealthScale(2));
  });

  test('a lost run stops the wave and a new run starts over', () {
    final game = boot();
    game.pumpFixed(steps: stepsFor(breatherSeconds + spawnGapSeconds));
    final alive = creepCount(game);

    game.world.setState(GameStatus.lost);
    game.pumpFixed(steps: stepsFor(spawnGapSeconds * 3));
    expect(creepCount(game), 0);
    expect(alive, greaterThan(0));

    game.world.setState(GameStatus.playing);
    game.pumpFixed(steps: 2);
    expect(game.world.resource<Wave>().number, 0);
  });

  test('raiders join from the second wave', () {
    final game = boot();
    game.pumpFixed(steps: stepsFor(breatherSeconds));
    finishWave(game);

    game.pumpFixed(
      steps: stepsFor(breatherSeconds + spawnGapSeconds * waveSize(2)),
    );

    final raiders = game.world.query<Raider>().count();
    expect(raiders, waveSize(2) ~/ raiderEvery);
  });
}
