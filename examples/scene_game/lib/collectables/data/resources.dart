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

const int _deflectCapacity = 40;
const double _deflectDuration = 0.4;

/// Pooled instanced shield-deflection VFX — no new scene node per deflection.
final class ShieldDeflectVfx {
  InstancedPool? pool;

  final Float32List age = Float32List(_deflectCapacity)
    ..fillRange(0, _deflectCapacity, _deflectDuration);
  final Float32List origin = Float32List(_deflectCapacity * 3);
  int _cursor = 0;

  void emit(Vector3 position) {
    age[_cursor] = 0;
    origin[_cursor * 3] = position.x;
    origin[_cursor * 3 + 1] = position.y;
    origin[_cursor * 3 + 2] = position.z;
    _cursor = (_cursor + 1) % _deflectCapacity;
  }

  void reset() => age.fillRange(0, _deflectCapacity, _deflectDuration);
}
