import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

void main() {
  test('defaults to real time', () {
    final clock = GameClock();
    expect(clock.timeScale, 1.0);
    expect(clock.paused, isFalse);
    expect(clock.freezeRemaining, 0);
    expect(clock.effectiveScale, 1.0);
  });

  test('timeScale scales and clamps negatives to zero', () {
    final clock = GameClock()..timeScale = 0.5;
    expect(clock.effectiveScale, 0.5);

    clock.timeScale = -3;
    expect(clock.timeScale, 0);
    expect(clock.effectiveScale, 0);
  });

  test('paused gates to zero and restores the prior scale on unpause', () {
    final clock = GameClock()
      ..timeScale = 0.25
      ..paused = true;
    expect(clock.effectiveScale, 0);

    clock.paused = false;
    expect(clock.effectiveScale, 0.25);
  });

  test('freezeFor stops time until served in wall time', () {
    final clock = GameClock()..freezeFor(0.05);
    expect(clock.effectiveScale, 0);

    clock.advanceFreeze(0.016);
    expect(clock.effectiveScale, 0);

    clock.advanceFreeze(0.016);
    clock.advanceFreeze(0.016);
    // 48ms served of a 50ms freeze; the next frame finishes it.
    expect(clock.effectiveScale, 0);
    clock.advanceFreeze(0.016);
    expect(clock.freezeRemaining, 0);
    expect(clock.effectiveScale, 1.0);
  });

  test('overlapping freezes extend to the longest, not the sum', () {
    final clock = GameClock()..freezeFor(0.06);
    clock.advanceFreeze(0.02); // 40ms left
    clock.freezeFor(0.03); // shorter than what's left: absorbed
    expect(clock.freezeRemaining, closeTo(0.04, 1e-12));

    clock.freezeFor(0.1); // longer: extends
    expect(clock.freezeRemaining, 0.1);
  });

  test('freezes do not drain while paused', () {
    final clock = GameClock()
      ..freezeFor(0.05)
      ..paused = true;
    clock.advanceFreeze(1.0);
    expect(clock.freezeRemaining, 0.05);

    clock.paused = false;
    clock.advanceFreeze(0.02);
    expect(clock.freezeRemaining, closeTo(0.03, 1e-12));
  });
}
