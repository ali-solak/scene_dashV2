import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:scene_game/game/game_state.dart';
import 'package:scene_game/rocks/data/config.dart';
import 'package:scene_game/rocks/rocks.dart';

/// Pure-logic coverage for the deterministic, seeded rock spawner — no scene or
/// GPU (it builds no rock meshes, only advances the timer and RNG) — plus the
/// spawner's life as a run-scoped process entity.
void main() {
  group('rock-spawner process entity', () {
    // Headless with the real feature; pumps stay well under the spawn
    // interval so no rock bundle (GPU materials) is ever built.
    TestGame boot() => TestGame.headless(
      strictAccess: true,
      features: [
        (g) {
          g.addState<GameStatus>(GameStatus.playing);
          g.world.insert(GameState());
        },
        installRocks,
      ],
    )..start();

    test('exists while playing and is absent outside it', () {
      final game = boot();
      expect(game.world.query<RockSpawner>().count(), 1);

      game.world.setState(GameStatus.lost);
      game.pump();
      expect(game.world.query<RockSpawner>().isEmpty, isTrue,
          reason: 'DespawnOnExit swept the process entity');

      game.world.setState(GameStatus.playing);
      game.pump();
      expect(game.world.query<RockSpawner>().count(), 1);
    });

    test('a second run starts with fresh cadence', () {
      final game = boot();
      final first = game.world.single<RockSpawner>();
      game.pumpFixed(steps: 5); // accumulate cadence, well under one due

      game.world.setState(GameStatus.lost);
      game.pump();
      game.world.setState(GameStatus.playing);
      game.pump();

      final second = game.world.single<RockSpawner>();
      expect(identical(first, second), isFalse,
          reason: 'respawn-per-run IS the cadence reset');
    });
  });

  test('tick releases a rock once the interval is exceeded', () {
    final spawner = RockSpawner(seed: 1);
    final interval = rockSpawnIntervalForSurvival(0);

    expect(spawner.tick(interval * 0.5, survived: 0), 0, reason: 'not due yet');
    expect(
      spawner.tick(interval * 0.6, survived: 0),
      1,
      reason: 'now past one interval',
    );
  });

  test('a large step releases several rocks at once', () {
    final spawner = RockSpawner(seed: 1);
    final interval = rockSpawnIntervalForSurvival(0);
    expect(spawner.tick(interval * 3.2, survived: 0), 3);
  });

  test('reset clears the accumulated time', () {
    final spawner = RockSpawner(seed: 1);
    final interval = rockSpawnIntervalForSurvival(0);
    spawner.tick(interval * 0.9, survived: 0); // accumulate, none due
    spawner.reset();
    expect(
      spawner.tick(interval * 0.5, survived: 0),
      0,
      reason: 'accumulator was reset',
    );
  });

  test('the same seed produces an identical spawn sequence', () {
    final a = RockSpawner(seed: 42);
    final b = RockSpawner(seed: 42);
    for (var i = 0; i < 8; i++) {
      expect(a.nextLane(), b.nextLane());
      expect(a.nextIsFlaming(i.toDouble()), b.nextIsFlaming(i.toDouble()));
    }
  });

  test('lanes stay within the spawn band', () {
    final spawner = RockSpawner(seed: 7);
    for (var i = 0; i < 50; i++) {
      expect(spawner.nextLane().abs(), lessThanOrEqualTo(rockSpawnHalfWidth));
    }
  });
}
