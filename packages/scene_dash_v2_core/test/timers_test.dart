import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

void main() {
  group('GameTimer (one-shot)', () {
    test('finishes exactly once and latches', () {
      final timer = GameTimer(0.05);
      timer.tick(0.016);
      expect(timer.finished, isFalse);
      expect(timer.justFinished, isFalse);

      timer
        ..tick(0.016)
        ..tick(0.016)
        ..tick(0.016);
      expect(timer.finished, isTrue);
      expect(timer.justFinished, isTrue);
      expect(timer.completionsThisTick, 1);

      timer.tick(0.016);
      expect(timer.finished, isTrue, reason: 'latched');
      expect(timer.justFinished, isFalse, reason: 'only on the crossing tick');
      expect(timer.completionsThisTick, 0);
    });

    test('elapsed clamps at duration; fraction and remaining track it', () {
      final timer = GameTimer(0.1)..tick(0.06);
      expect(timer.fraction, closeTo(0.6, 1e-12));
      expect(timer.remaining, closeTo(0.04, 1e-12));

      timer.tick(1.0);
      expect(timer.elapsed, 0.1);
      expect(timer.fraction, 1);
      expect(timer.remaining, 0);
    });

    test('reset restarts, optionally with a new duration', () {
      final timer = GameTimer(0.05)..tick(0.1);
      expect(timer.finished, isTrue);

      timer.reset();
      expect(timer.finished, isFalse);
      expect(timer.elapsed, 0);

      timer.reset(0.2);
      timer.tick(0.1);
      expect(timer.finished, isFalse);
      expect(timer.fraction, closeTo(0.5, 1e-12));
    });
  });

  group('GameTimer (repeating)', () {
    test('completes each period and rolls overshoot forward', () {
      final timer = GameTimer.repeating(0.05);
      timer.tick(0.06);
      expect(timer.justFinished, isTrue);
      expect(timer.completionsThisTick, 1);
      expect(timer.elapsed, closeTo(0.01, 1e-12));

      timer.tick(0.02);
      expect(timer.justFinished, isFalse);
      expect(timer.completionsThisTick, 0);
    });

    test('a tick spanning several periods reports every completion', () {
      final timer = GameTimer.repeating(0.5);
      timer.tick(2.3); // frame hitch
      expect(timer.completionsThisTick, 4);
      expect(timer.justFinished, isTrue);
      expect(timer.elapsed, closeTo(0.3, 1e-9));
    });

    test('average rate is exact across uneven frames', () {
      final timer = GameTimer.repeating(0.05);
      var completions = 0;
      var time = 0.0;
      // Uneven frame pattern summing to exactly 1 second.
      const deltas = [0.016, 0.033, 0.017, 0.014, 0.02];
      while (time < 1.0 - 1e-9) {
        for (final dt in deltas) {
          timer.tick(dt);
          completions += timer.completionsThisTick;
          time += dt;
        }
      }
      expect(completions, 20, reason: '1 second at 20 Hz');
    });
  });

  test('GameStopwatch accumulates and resets', () {
    final watch = GameStopwatch()
      ..tick(0.016)
      ..tick(0.016);
    expect(watch.elapsed, closeTo(0.032, 1e-12));
    watch.reset();
    expect(watch.elapsed, 0);
  });
}
