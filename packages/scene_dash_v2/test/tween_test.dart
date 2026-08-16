import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart';

/// A would-be pop curve, to pin down why pops are not curves.
class _PopCurve extends Curve {
  const _PopCurve();

  @override
  double transformInternal(double t) => math.sin(t * math.pi);
}

void main() {
  group('progress', () {
    test('fraction, eased and value walk from -> to', () {
      final tween = GameTween.number(10, 20, 1);
      expect(tween.fraction, 0);
      expect(tween.value, 10);

      tween.tick(0.25);
      expect(tween.fraction, 0.25);
      expect(tween.eased, 0.25, reason: 'no curve is linear');
      expect(tween.value, 12.5);

      tween.tick(0.75);
      expect(tween.fraction, 1);
      expect(tween.value, 20);
    });

    test('a curve bends eased but not fraction', () {
      final tween = GameTween.number(0, 1, 1, curve: Curves.easeInOutCubic);
      tween.tick(0.25);

      expect(tween.fraction, 0.25);
      expect(tween.eased, closeTo(Curves.easeInOutCubic.transform(0.25), 1e-12));
      expect(tween.value, tween.eased, reason: '0 -> 1 makes value == eased');
    });

    test('eased is not clamped, so anticipation curves keep overshooting', () {
      final tween = GameTween.number(0, 1, 1, curve: Curves.easeOutBack);
      var peak = 0.0;
      for (var i = 0; i < 20; i++) {
        tween.tick(0.05);
        if (tween.eased > peak) peak = tween.eased;
      }

      expect(peak, greaterThan(1.0), reason: 'guards against a .clamp here');
      expect(tween.eased, 1.0, reason: 'and still lands exactly on to');
    });

    test('duration shortens in place and clamps elapsed', () {
      final tween = GameTween.number(0, 1, 1)..tick(0.8);
      tween.duration = 0.5;

      expect(tween.elapsed, 0.5);
      expect(tween.finished, isTrue);
    });
  });

  group('edges match GameTimer', () {
    test('same fraction, finished and justFinished, tick for tick', () {
      final timer = GameTimer(0.5);
      final tween = GameTween.number(0, 1, 0.5);

      for (final delta in <double>[0.1, 0.2, 0.15, 0.1, 0.1, 0.3]) {
        timer.tick(delta);
        tween.tick(delta);
        expect(tween.fraction, timer.fraction, reason: 'after $delta');
        expect(tween.elapsed, timer.elapsed, reason: 'after $delta');
        expect(tween.finished, timer.finished, reason: 'after $delta');
        expect(tween.justFinished, timer.justFinished, reason: 'after $delta');
      }
    });

    test('justFinished is true for exactly one tick and latches finished', () {
      final tween = GameTween.number(0, 1, 0.2)..tick(0.3);
      expect(tween.justFinished, isTrue);
      expect(tween.value, 1, reason: 'no overshoot past to');

      tween.tick(0.3);
      expect(tween.justFinished, isFalse);
      expect(tween.finished, isTrue);
      expect(tween.value, 1);
    });

    test('tick(0) clears the edge and leaves the value alone', () {
      final tween = GameTween.number(0, 1, 0.2)..tick(0.3);
      expect(tween.justFinished, isTrue);

      tween.tick(0);
      expect(tween.justFinished, isFalse);
      expect(tween.value, 1);
    });

    test('a zero duration is rejected, because its edge could never fire', () {
      expect(() => GameTween.number(0, 1, 0), throwsA(isA<AssertionError>()));
    });
  });

  group('retarget', () {
    test('bends mid-flight without a step', () {
      final tween = GameTween.number(0, 10, 1)..tick(0.4);
      final before = tween.value;

      tween.retarget(-5);

      expect(tween.value, before, reason: 'from is the value, not the fraction');
      expect(tween.from, before);
      expect(tween.elapsed, 0);
      expect(tween.duration, 1, reason: 'travel time is constant');
    });

    test('un-finishes a finished tween', () {
      final tween = GameTween.number(0, 1, 0.2)..tick(0.3);
      expect(tween.finished, isTrue);

      tween.retarget(0);
      expect(tween.finished, isFalse);
      expect(tween.value, 1);
    });

    test('clears a reversal', () {
      final tween = GameTween.number(0, 1, 1)
        ..tick(0.5)
        ..reverse();
      expect(tween.reversed, isTrue);

      tween.retarget(2);
      expect(tween.reversed, isFalse);
    });
  });

  group('reverse', () {
    test('is continuous across the call, even on an asymmetric curve', () {
      final tween = GameTween.number(1, 1.25, 1, curve: Curves.easeOutBack)
        ..tick(0.4);
      final before = tween.value;

      tween.reverse();

      expect(
        tween.value,
        before,
        reason: 'time runs backwards, so value is a function of elapsed only',
      );
    });

    test('twice is an exact identity', () {
      final tween = GameTween.number(0, 10, 1, curve: Curves.easeOutBack)
        ..tick(0.35);
      final value = tween.value;
      final elapsed = tween.elapsed;

      tween
        ..reverse()
        ..reverse();

      expect(tween.reversed, isFalse);
      expect(tween.elapsed, elapsed);
      expect(tween.value, value);
    });

    test('retraces the path back to from and reports the edge', () {
      final tween = GameTween.number(1, 1.25, 0.2)..tick(0.3);
      expect(tween.justFinished, isTrue);

      tween.reverse();
      expect(tween.finished, isFalse, reason: 'the far end is now the start');

      tween.tick(0.1);
      expect(tween.value, closeTo(1.125, 1e-12));
      expect(tween.justFinished, isFalse);

      tween.tick(0.2);
      expect(tween.value, 1);
      expect(tween.justFinished, isTrue);
      expect(tween.finished, isTrue);
    });

    test('before the first tick finishes immediately', () {
      final tween = GameTween.number(0, 1, 1)..reverse();

      expect(tween.finished, isTrue);
      expect(tween.value, 0);
    });

    test('leaves justFinished alone, so the edge survives the frame', () {
      final tween = GameTween.number(0, 1, 0.2)..tick(0.3);

      tween.reverse();

      expect(
        tween.justFinished,
        isTrue,
        reason: 'systems later in the frame must still see the edge',
      );
    });
  });

  group('why a pop is not a Curve', () {
    test('Curve.transform pins the endpoints', () {
      const pop = _PopCurve();

      expect(pop.transform(0.5), closeTo(1.0, 1e-12));
      expect(
        pop.transform(1.0),
        1.0,
        reason: 'Curve.transform short-circuits t == 1 to 1, not sin(pi) == 0',
      );
    });

    test('so the pop is built from reverse instead', () {
      final scale = GameTween.number(1, 1.25, 0.1, curve: Curves.easeOutBack);
      scale.tick(0.2);
      expect(scale.justFinished, isTrue);

      scale.reverse();
      scale.tick(0.2);

      expect(scale.justFinished, isTrue);
      expect(scale.value, 1, reason: 'ends where it started');
    });
  });

  group('vectors', () {
    test('valueInto agrees with value and writes into the caller', () {
      final tween = vector3Tween(Vector3.zero(), Vector3(2, 4, 6), 1)
        ..tick(0.5);
      final out = Vector3.zero();

      tween.valueInto(out);

      expect(out.x, tween.value.x);
      expect(out.y, tween.value.y);
      expect(out.z, tween.value.z);
      expect(out.y, 2);
    });

    test('endpoints are copied, so a live vector cannot drag the tween', () {
      final live = Vector3(0, 0, 0);
      final tween = vector3Tween(live, Vector3(10, 0, 0), 1);

      live.setValues(100, 100, 100);
      tween.tick(0.5);

      expect(tween.value.x, 5);
      expect(tween.value.y, 0);
    });

    test('colorTween mixes all four channels', () {
      final tween = colorTween(Vector4(0, 0, 0, 1), Vector4(1, 1, 1, 0), 1)
        ..tick(0.25);
      final out = Vector4.zero();

      tween.valueInto(out);

      expect(out.x, 0.25);
      expect(out.w, 0.75);
    });
  });

  test('toString reports progress and time', () {
    final tween = GameTween.number(0, 1, 0.5)..tick(0.35);

    expect(tween.toString(), '70% (0.35/0.50s)');

    tween.reverse();
    expect(tween.toString(), contains('reversed'));
  });
}
