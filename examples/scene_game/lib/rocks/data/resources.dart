part of '../rocks.dart';

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
