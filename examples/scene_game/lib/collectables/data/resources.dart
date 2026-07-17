part of '../collectables.dart';

/// Cadence + RNG for shield-pickup spawns.
final class CollectableSpawner {
  CollectableSpawner({int? seed}) : random = math.Random(seed);

  final math.Random random;
  final GameTimer _cadence = GameTimer.repeating(shieldPickupInterval);

  bool tick(double dt) {
    _cadence.tick(dt);
    return _cadence.justFinished;
  }

  double nextLane() =>
      (random.nextDouble() * 2 - 1) * shieldPickupSpawnHalfWidth;

  void reset() => _cadence.reset();
}
