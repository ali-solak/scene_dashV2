part of '../player.dart';

/// Player-owned shove state: rules decide when a rock contacted the player;
/// this decides how that becomes controller movement.
final class PlayerKnockback {
  final Vector3 _velocity = Vector3.zero();
  final Vector3 _displacement = Vector3.zero();
  double _fallVelocityY = 0;

  /// Adds a shove away from the rock; falls back to down-ramp when the centres
  /// overlap.
  void pushFromRock({
    required Vector3 playerPosition,
    required Vector3 rockPosition,
  }) {
    _velocity
      ..setFrom(playerPosition)
      ..sub(rockPosition)
      ..y = 0;
    if (_velocity.length2 < 0.001) {
      _velocity.setValues(0, 0, 1);
    } else {
      _velocity.normalize();
    }
    _velocity.scale(knockbackPushSpeed);
  }

  /// Returns this fixed step's horizontal displacement and damps the stored
  /// shove. The returned vector is rewritten by the next call — consume it
  /// within the same step.
  Vector3 step(double dt) {
    if (_velocity.length2 < 0.0001) {
      _velocity.setZero();
      return _displacement..setZero();
    }

    _displacement
      ..setFrom(_velocity)
      ..scale(dt);
    final speed = _velocity.length;
    final nextSpeed = (speed - knockbackDecayRate * dt).clamp(0.0, speed);
    if (nextSpeed == 0) {
      _velocity.setZero();
    } else {
      _velocity.scale(nextSpeed / speed);
    }
    return _displacement;
  }

  /// This fixed step's falling displacement while off the ramp.
  double fallStep(double dt) {
    _fallVelocityY -= gravityStrength * dt;
    return _fallVelocityY * dt;
  }

  void ground() => _fallVelocityY = 0;

  void reset() {
    _velocity.setZero();
    _fallVelocityY = 0;
  }
}
