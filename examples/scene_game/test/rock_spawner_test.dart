import 'package:flutter_test/flutter_test.dart';
import 'package:scene_game/rocks/data/config.dart';
import 'package:scene_game/rocks/rocks.dart';

/// Pure-logic coverage for the deterministic, seeded rock spawner — no scene or
/// GPU (it builds no rock meshes, only advances the timer and RNG).
void main() {
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
