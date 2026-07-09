import 'package:flutter_test/flutter_test.dart';
import 'package:scene_game/collectables/collectables.dart';
import 'package:scene_game/collectables/data/config.dart';

/// Pure-logic coverage for the global shield's activate/tick/absorb/reset
/// machine — no scene or GPU.
void main() {
  test('a fresh shield is inactive', () {
    final shield = ShieldState();
    expect(shield.active, isFalse);
    expect(shield.remaining, 0);
    expect(shield.normalized, 0);
    expect(shield.expiringSoon, isFalse);
  });

  test('activation gives a full-duration shield', () {
    final shield = ShieldState()..activate();
    expect(shield.active, isTrue);
    expect(shield.remaining, shieldDuration);
    expect(shield.normalized, 1.0);
  });

  test('activation while active refreshes back to full', () {
    final shield = ShieldState()..activate();
    shield.tick(shieldDuration * 0.6);
    expect(shield.remaining, closeTo(shieldDuration * 0.4, 1e-9));
    shield.activate();
    expect(shield.remaining, shieldDuration);
  });

  test('ticking counts down and never goes negative', () {
    final shield = ShieldState()..activate();
    shield.tick(shieldDuration + 5);
    expect(shield.remaining, 0);
    expect(shield.active, isFalse);
  });

  test('the warning window begins in the final seconds', () {
    final shield = ShieldState()..activate();
    shield.tick(shieldDuration - shieldWarningWindow - 0.1);
    expect(shield.expiringSoon, isFalse);
    shield.tick(0.2);
    expect(shield.expiringSoon, isTrue);
  });

  test('absorbing a hit costs a little time but never goes negative', () {
    final shield = ShieldState()..activate();
    final before = shield.remaining;
    shield.absorbHit();
    expect(shield.remaining, closeTo(before - shieldDeflectTimeCost, 1e-9));

    shield.tick(shieldDuration); // drain almost fully
    shield.absorbHit();
    expect(shield.remaining, 0);
  });

  test('reset clears the shield', () {
    final shield = ShieldState()
      ..activate()
      ..reset();
    expect(shield.active, isFalse);
    expect(shield.remaining, 0);
  });
}
