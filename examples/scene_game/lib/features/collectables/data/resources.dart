part of '../collectables.dart';

final class PickupLanes {
  PickupLanes({int? seed}) : random = math.Random(seed);

  final math.Random random;

  double nextLane() =>
      (random.nextDouble() * 2 - 1) * shieldPickupSpawnHalfWidth;
}
