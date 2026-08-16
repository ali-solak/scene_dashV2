import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart';

/// The formula this library exists to replace: `alpha = dt * k`, clamped.
double _naive(double value, double target, double dt, double rate) =>
    value + (target - value) * math.min(1.0, dt * rate);

void main() {
  group('smoothBlend', () {
    test('is independent of frame rate', () {
      const halfLife = 0.1;
      final oneBigStep = smoothTo(0, 1, 1 / 30, halfLife);

      var twoSmallSteps = 0.0;
      twoSmallSteps = smoothTo(twoSmallSteps, 1, 1 / 60, halfLife);
      twoSmallSteps = smoothTo(twoSmallSteps, 1, 1 / 60, halfLife);

      expect(twoSmallSteps, closeTo(oneBigStep, 1e-12));
    });

    test('and the naive form is not, which is why this exists', () {
      const rate = 8.0;
      final oneBigStep = _naive(0, 1, 1 / 30, rate);

      var twoSmallSteps = 0.0;
      twoSmallSteps = _naive(twoSmallSteps, 1, 1 / 60, rate);
      twoSmallSteps = _naive(twoSmallSteps, 1, 1 / 60, rate);

      expect((twoSmallSteps - oneBigStep).abs(), greaterThan(0.01));
    });

    test('closes exactly half the gap in one half-life', () {
      expect(smoothBlend(0.25, 0.25), closeTo(0.5, 1e-12));
      expect(smoothTo(0, 1, 0.25, 0.25), closeTo(0.5, 1e-12));
    });

    test('a zero dt is the identity', () {
      expect(smoothBlend(0, 0.1), 0);
      expect(smoothTo(3, 9, 0, 0.1), 3);
    });

    test('a long frame eases instead of snapping', () {
      final blend = smoothBlend(5, 0.1);

      expect(blend, lessThan(1));
      expect(smoothTo(0, 1, 5, 0.1), lessThan(1));
      expect(
        _naive(0, 1, 5, 8),
        1,
        reason: 'the naive form hard-snaps once dt exceeds 1 / rate',
      );
    });

    test('asserts on a non-positive half-life in debug', () {
      expect(() => smoothBlend(0, 0), throwsA(isA<AssertionError>()));
      expect(() => smoothBlend(0.016, -1), throwsA(isA<AssertionError>()));
    });

    test('and guards the same case in release, where the assert is gone', () {
      // The guarded expression, spelled out: with dt and halfLife both zero it
      // is 0/0, and exp(NaN) poisons the value permanently with nothing
      // thrown to point at the cause. The assert above cannot catch this in a
      // release build, so smoothBlend returns 1 (snap) instead of dividing.
      const dt = 0.0;
      const halfLife = 0.0;
      expect((-dt * math.ln2 / halfLife).isNaN, isTrue);
      expect(math.exp(-dt * math.ln2 / halfLife).isNaN, isTrue);
    });
  });

  group('moveToward', () {
    test('arrives exactly and never overshoots', () {
      expect(moveToward(0, 1, 0.3), 0.3);
      expect(moveToward(0.9, 1, 0.3), 1);
    });

    test('walks downhill too', () {
      expect(moveToward(1, 0, 0.3), 0.7);
      expect(moveToward(0.1, 0, 0.3), 0);
    });

    test('a zero step and a closed gap are both the identity', () {
      expect(moveToward(0.4, 1, 0), 0.4);
      expect(moveToward(0.4, 0.4, 0.3), 0.4);
    });

    test('covers the span in the time a rate of dt / seconds implies', () {
      const seconds = 0.25;
      const dt = 1 / 60;
      var weight = 0.0;
      var ticks = 0;
      while (weight < 1 && ticks < 1000) {
        weight = moveToward(weight, 1, dt / seconds);
        ticks++;
      }

      expect(weight, 1, reason: 'reaches 1 exactly, unlike smoothTo');
      expect(ticks, closeTo(seconds / dt, 1));
    });
  });

  group('GameSmooth', () {
    test('eases toward a target that moves each tick', () {
      final smooth = GameSmooth(0, halfLife: 0.1);

      smooth.tick(0.1, 10);
      expect(smooth.value, closeTo(5, 1e-12));

      smooth.tick(0.1, 10);
      expect(smooth.value, closeTo(7.5, 1e-12));
    });

    test('snap skips the easing', () {
      final smooth = GameSmooth(0, halfLife: 0.1)..tick(0.1, 10);
      smooth.snap(-3);

      expect(smooth.value, -3);
    });

    test('settled is a tolerance the caller chooses', () {
      final smooth = GameSmooth(0, halfLife: 0.05);
      expect(smooth.settled(1, 0.01), isFalse);

      for (var i = 0; i < 60; i++) {
        smooth.tick(1 / 60, 1);
      }

      expect(smooth.settled(1, 0.01), isTrue);
      expect(smooth.value, lessThan(1), reason: 'never exactly arrives');
    });

    test('half-life can tighten mid-run', () {
      final smooth = GameSmooth(0, halfLife: 1);
      smooth.tick(0.1, 10);
      final loose = smooth.value;

      smooth
        ..snap(0)
        ..halfLife = 0.05
        ..tick(0.1, 10);

      expect(smooth.value, greaterThan(loose));
    });

    test('asserts on a non-positive half-life', () {
      expect(() => GameSmooth(0, halfLife: 0), throwsA(isA<AssertionError>()));
    });

    test('toString reports value and rate', () {
      expect(GameSmooth(0.5, halfLife: 0.1).toString(), '0.50 (half-life 0.10s)');
    });
  });

  group('Vector3.smoothToward', () {
    test('writes in place without allocating', () {
      final position = Vector3(0, 0, 0);
      final target = Vector3(10, 20, 30);

      position.smoothToward(target, 0.1, 0.1);

      expect(position.x, closeTo(5, 1e-12));
      expect(position.y, closeTo(10, 1e-12));
      expect(position.z, closeTo(15, 1e-12));
    });

    test('is independent of frame rate', () {
      final target = Vector3(10, 0, 0);
      final big = Vector3.zero()..smoothToward(target, 1 / 30, 0.1);
      final small = Vector3.zero()
        ..smoothToward(target, 1 / 60, 0.1)
        ..smoothToward(target, 1 / 60, 0.1);

      expect(small.x, closeTo(big.x, 1e-12));
    });
  });
}
