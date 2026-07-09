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

/// The single global shield; [ShieldView] lets the HUD read it without
/// depending on the collectables feature.
///
/// A countdown over a [GameTimer]: the timer runs *up* toward expiry, so
/// "remaining" is [GameTimer.remaining], activation is a [GameTimer.reset],
/// and the deflect cost is served by ticking the timer forward.
final class ShieldState {
  ShieldState() {
    _expire();
  }

  final GameTimer _life = GameTimer(shieldDuration);

  bool get active => !_life.finished;

  double get remaining => _life.remaining;

  double get normalized => 1 - _life.fraction;

  bool get expiringSoon => active && _life.remaining <= shieldWarningWindow;

  /// Activates or refreshes the shield to its full duration.
  void activate() => _life.reset();

  void tick(double dt) => _life.tick(dt);

  /// Deflecting a rock consumes some remaining time.
  void absorbHit() => _life.tick(shieldDeflectTimeCost);

  void reset() => _expire();

  /// Fast-forwards the timer to finished, so a fresh/reset shield is down.
  void _expire() {
    _life
      ..reset()
      ..tick(shieldDuration);
  }
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
