part of '../rocks.dart';

/// The shared flame-trail emitter, held on a scene-scoped process entity.
/// Headless worlds have no carrier at all, so `singleOrNull` is the only
/// absence check and every field is non-null.
final class FlameTrailEmitter {
  FlameTrailEmitter({required this.shape, required this.spawner});

  /// The spawn shape carrying the flaming rocks' world positions.
  final FlameTrailShape shape;

  /// The emitter's spawner; its rate scales with the flaming-rock count.
  final fx.Spawner spawner;
}

/// Spawn cadence plus RNG, injected as a resource.
final class RockSpawner {
  final math.Random random;

  /// Difficulty-scaled cadence: the duration is retuned each step before
  /// the tick, and `completionsThisTick` is exactly "rocks due", including
  /// the catch-up after a frame hitch.
  final GameTimer _cadence = GameTimer.repeating(
    rockSpawnIntervalForSurvival(0),
  );

  RockSpawner({int? seed}) : random = math.Random(seed);

  /// Returns the number of rocks due this step.
  int tick(double dt, {required double survived}) {
    _cadence
      ..duration = rockSpawnIntervalForSurvival(survived)
      ..tick(dt);
    return _cadence.completionsThisTick;
  }

  double nextLane() => (random.nextDouble() * 2 - 1) * rockSpawnHalfWidth;

  bool nextIsFlaming(double survived) {
    return random.nextDouble() < flamingRockChanceForSurvival(survived);
  }

  void reset() => _cadence.reset();
}
