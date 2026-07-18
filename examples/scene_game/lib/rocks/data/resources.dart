part of '../rocks.dart';

/// The single shared flame-trail emitter — a component on a scene-scoped
/// process entity spawned by `spawnFlameTrailEmitter` (startup,
/// scene-gated) and steered by `updateFlameTrails`. Headless worlds simply
/// have no carrier: `singleOrNull` is the one absence check, and every
/// field is non-null by construction (the state doctrine — a feature's
/// process is a component, not a nullable-field resource).
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
