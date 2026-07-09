import 'package:flutter_test/flutter_test.dart';
import 'package:scene_game/player/data/config.dart';
import 'package:scene_game/player/player.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

/// Pure-logic coverage for rock-contact shove state (no scene or GPU).
void main() {
  test('a fresh knockback state returns no displacement', () {
    final knockback = PlayerKnockback();
    final displacement = knockback.step(0.1);

    expect(displacement.length, 0);
  });

  test('a rock behind the player pushes down the ramp', () {
    const dt = 0.1;
    final knockback = PlayerKnockback()
      ..pushFromRock(
        playerPosition: Vector3(0, 5, 0),
        rockPosition: Vector3(0, 5, -1),
      );

    final displacement = knockback.step(dt);

    expect(displacement.x, closeTo(0, 1e-9));
    expect(displacement.z, closeTo(knockbackPushSpeed * dt, 1e-6));
  });

  test('overlapping centres fall back to down-ramp shove', () {
    const dt = 0.1;
    final knockback = PlayerKnockback()
      ..pushFromRock(
        playerPosition: Vector3(0, 5, 0),
        rockPosition: Vector3(0, 5, 0),
      );

    final displacement = knockback.step(dt);

    expect(displacement.x, closeTo(0, 1e-9));
    expect(displacement.z, closeTo(knockbackPushSpeed * dt, 1e-6));
  });

  test('step damps the shove and reset clears it', () {
    const dt = 0.1;
    final knockback = PlayerKnockback()
      ..pushFromRock(
        playerPosition: Vector3(1, 5, 0),
        rockPosition: Vector3(0, 5, 0),
      );

    // step() returns one reused scratch vector, so consume each result
    // before the next call — the same contract gameplay code follows.
    final firstLength = knockback.step(dt).length;
    final secondLength = knockback.step(dt).length;
    knockback.reset();
    final afterResetLength = knockback.step(dt).length;

    expect(firstLength, closeTo(knockbackPushSpeed * dt, 1e-6));
    expect(secondLength, lessThan(firstLength));
    expect(afterResetLength, 0);
  });

  test('fall step accelerates downward until grounded', () {
    const dt = 0.1;
    final knockback = PlayerKnockback();

    final first = knockback.fallStep(dt);
    final second = knockback.fallStep(dt);
    knockback.ground();
    final afterGround = knockback.fallStep(dt);

    expect(first, lessThan(0));
    expect(second, lessThan(first));
    expect(afterGround, closeTo(first, 1e-9));
  });
}
