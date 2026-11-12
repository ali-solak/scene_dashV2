import 'package:flutter_test/flutter_test.dart';
import 'package:scene_game/features/projectiles/data/config.dart';
import 'package:scene_game/features/projectiles/projectiles.dart';

/// Pure-logic coverage for the blaster's tap-to-burst / hold-to-charge state
/// machine. Drives [Blaster.update] directly — no scene or GPU.
void main() {
  const frame = 1 / 60;

  // Sums burst pellets and counts charged shots over [steps] idle steps.
  ({int burst, int charged}) drainIdle(Blaster b, {int steps = 12}) {
    var burst = 0;
    var charged = 0;
    for (var i = 0; i < steps; i++) {
      final s = b.update(
        pressed: false,
        released: false,
        held: false,
        dt: blasterBurstInterval,
      );
      burst += s.burst;
      if (s.charged != null) charged++;
    }
    return (burst: burst, charged: charged);
  }

  test('a fresh blaster is ready', () {
    expect(Blaster().isReady, isTrue);
  });

  test('a quick tap fires the normal burst', () {
    final b = Blaster();
    // Press and release within one step, well under the charge threshold.
    final s = b.update(pressed: true, released: true, held: false, dt: frame);
    var burst = s.burst;
    expect(s.charged, isNull);
    burst += drainIdle(b).burst;
    expect(burst, blasterBurstShots);
  });

  test('holding below the threshold then releasing is still a burst', () {
    final b = Blaster()
      ..update(pressed: true, released: false, held: true, dt: 0);
    // Hold for less than the threshold.
    b.update(
      pressed: false,
      released: false,
      held: true,
      dt: blasterChargeThreshold * 0.5,
    );
    expect(b.isCharging, isFalse, reason: 'not past the threshold yet');
    final s = b.update(pressed: false, released: true, held: false, dt: 0);
    expect(s.charged, isNull);
    final totals = drainIdle(b);
    expect(s.burst + totals.burst, blasterBurstShots);
    expect(totals.charged, 0);
  });

  test('holding past the threshold enters the charging state', () {
    final b = Blaster()
      ..update(pressed: true, released: false, held: true, dt: 0)
      ..update(
        pressed: false,
        released: false,
        held: true,
        dt: blasterChargeThreshold + 0.02,
      );
    expect(b.isCharging, isTrue);
    expect(b.charge01, greaterThan(0));
  });

  test('a charged release produces exactly one charged shot', () {
    final b = Blaster()
      ..update(pressed: true, released: false, held: true, dt: 0)
      ..update(
        pressed: false,
        released: false,
        held: true,
        dt: blasterChargeThreshold + 0.2,
      );
    final s = b.update(pressed: false, released: true, held: false, dt: 0);
    expect(s.charged, isNotNull);
    expect(s.burst, 0);
    // No further shots come out afterwards.
    final totals = drainIdle(b);
    expect(totals.burst, 0);
    expect(totals.charged, 0);
  });

  test('charge clamps at maximum', () {
    final b = Blaster()
      ..update(pressed: true, released: false, held: true, dt: 0)
      ..update(
        pressed: false,
        released: false,
        held: true,
        dt: blasterMaxChargeDuration * 2,
      );
    expect(b.charge01, 1.0);
  });

  test('cooldown blocks a new fire sequence', () {
    final b = Blaster()
      ..update(pressed: true, released: false, held: true, dt: 0)
      ..update(
        pressed: false,
        released: false,
        held: true,
        dt: blasterChargeThreshold + 0.2,
      )
      ..update(pressed: false, released: true, held: false, dt: 0);
    expect(b.isCoolingDown, isTrue);
    expect(b.isReady, isFalse);

    // A press while cooling down does nothing.
    final blocked = b.update(
      pressed: true,
      released: false,
      held: true,
      dt: 0.1,
    );
    expect(blocked.isEmpty, isTrue);

    // Draining the cooldown re-arms the blaster.
    b.update(
      pressed: false,
      released: false,
      held: false,
      dt: chargedShotCooldown,
    );
    expect(b.isReady, isTrue);
  });

  test('cancel does not fire', () {
    final b = Blaster()
      ..update(pressed: true, released: false, held: true, dt: 0)
      ..update(
        pressed: false,
        released: false,
        held: true,
        dt: blasterChargeThreshold + 0.2,
      );
    final s = b.update(pressed: false, released: false, held: false, dt: 0);
    expect(s.isEmpty, isTrue);
    expect(b.isReady, isTrue);
    expect(drainIdle(b).charged, 0);
  });

  test('phase edges follow the machine latch: charging-started is readable '
      'until the next update', () {
    final b = Blaster()
      ..update(pressed: true, released: false, held: true, dt: 0);
    // The HUD's charging-started signal — a machine edge, no bookkeeping.
    expect(b.phase.justEntered(BlasterPhase.charging), isTrue);
    b.update(pressed: false, released: false, held: true, dt: frame);
    expect(
      b.phase.justEntered(BlasterPhase.charging),
      isFalse,
      reason: 'the next update ticks the machine: window closed',
    );
    expect(b.phase.state, BlasterPhase.charging);
  });

  test('reset clears all state', () {
    final b = Blaster()
      ..update(pressed: true, released: false, held: true, dt: 0)
      ..update(pressed: false, released: false, held: true, dt: 0.5)
      ..reset();
    expect(b.isReady, isTrue);
    expect(b.charge01, 0);
    expect(b.cooldown01, 0);
    expect(b.isCoolingDown, isFalse);
  });
}
