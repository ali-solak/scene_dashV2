part of '../collectables.dart';

/// Lane RNG for shield-pickup spawns. The cadence itself lives at
/// registration — `runIf: every(shieldPickupInterval)` — per the
/// run-conditions doctrine (periodicity at registration, never a timer
/// resource), so this resource carries only the seeded randomness.
final class PickupLanes {
  PickupLanes({int? seed}) : random = math.Random(seed);

  final math.Random random;

  double nextLane() =>
      (random.nextDouble() * 2 - 1) * shieldPickupSpawnHalfWidth;
}
