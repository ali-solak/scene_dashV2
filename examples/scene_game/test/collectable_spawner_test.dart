import 'package:flutter_test/flutter_test.dart';
import 'package:scene_game/collectables/collectables.dart';
import 'package:scene_game/collectables/data/config.dart';

/// Pure-logic coverage for the seeded shield-pickup spawner cadence — no scene.
void main() {
  test('tick is due only once the interval is exceeded', () {
    final spawner = CollectableSpawner(seed: 1);
    expect(spawner.tick(shieldPickupInterval * 0.5), isFalse);
    expect(spawner.tick(shieldPickupInterval * 0.6), isTrue);
  });

  test('a fresh interval is required after a spawn', () {
    final spawner = CollectableSpawner(seed: 1);
    expect(spawner.tick(shieldPickupInterval), isTrue);
    // Accumulator reset on the due tick: not immediately due again.
    expect(spawner.tick(shieldPickupInterval * 0.5), isFalse);
  });

  test('reset clears the accumulated time', () {
    final spawner = CollectableSpawner(seed: 1);
    spawner.tick(shieldPickupInterval * 0.9);
    spawner.reset();
    expect(spawner.tick(shieldPickupInterval * 0.5), isFalse);
  });

  test('lanes stay within the spawn band', () {
    final spawner = CollectableSpawner(seed: 7);
    for (var i = 0; i < 50; i++) {
      expect(
        spawner.nextLane().abs(),
        lessThanOrEqualTo(shieldPickupSpawnHalfWidth),
      );
    }
  });
}
