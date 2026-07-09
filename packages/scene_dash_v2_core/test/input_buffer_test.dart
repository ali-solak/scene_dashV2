import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

enum _Action { attack, roll, parry }

void main() {
  group('InputBuffer', () {
    test('a recorded action is consumable exactly once', () {
      final buffer = InputBuffer<_Action>();
      buffer.record(_Action.attack);
      expect(buffer.consume(_Action.attack), isTrue);
      expect(buffer.consume(_Action.attack), isFalse);
    });

    test('expiry at exactly the window boundary is inclusive', () {
      final buffer = InputBuffer<_Action>(window: 0.15);
      buffer.record(_Action.roll);

      // Exactly `window` old: still live.
      buffer.advance(0.15);
      expect(buffer.has(_Action.roll), isTrue);

      // Strictly past the window: expired.
      buffer.advance(0.0001);
      expect(buffer.has(_Action.roll), isFalse);
      expect(buffer.consume(_Action.roll), isFalse);
    });

    test('consume takes the oldest matching entry first', () {
      final buffer = InputBuffer<_Action>(window: 1.0);
      buffer.record(_Action.attack);
      buffer.advance(0.1);
      buffer.record(_Action.attack);

      // Consuming removes the older press; the newer one (0.1s younger)
      // survives past the point where the older one would have expired.
      expect(buffer.consume(_Action.attack), isTrue);
      buffer.advance(0.95);
      expect(buffer.has(_Action.attack), isTrue);
      expect(buffer.consume(_Action.attack), isTrue);
      expect(buffer.consume(_Action.attack), isFalse);
    });

    test('consume removes only the matched action, leaving others in place', () {
      final buffer = InputBuffer<_Action>(window: 1.0);
      buffer.record(_Action.attack);
      buffer.record(_Action.roll);
      buffer.record(_Action.attack);

      expect(buffer.consume(_Action.roll), isTrue);
      expect(buffer.has(_Action.roll), isFalse);
      expect(buffer.consume(_Action.attack), isTrue);
      expect(buffer.consume(_Action.attack), isTrue);
      expect(buffer.consume(_Action.attack), isFalse);
    });

    test('consumeAny returns the oldest entry across the given actions', () {
      final buffer = InputBuffer<_Action>(window: 1.0);
      buffer.record(_Action.roll);
      buffer.record(_Action.attack);

      expect(
        buffer.consumeAny(<_Action>{_Action.attack, _Action.roll}),
        _Action.roll,
      );
      expect(
        buffer.consumeAny(<_Action>{_Action.attack, _Action.roll}),
        _Action.attack,
      );
      expect(
        buffer.consumeAny(<_Action>{_Action.attack, _Action.roll}),
        isNull,
      );
    });

    test('consumeAny skips actions outside the set', () {
      final buffer = InputBuffer<_Action>(window: 1.0);
      buffer.record(_Action.parry);
      buffer.record(_Action.attack);

      expect(buffer.consumeAny(<_Action>{_Action.attack}), _Action.attack);
      expect(buffer.has(_Action.parry), isTrue);
    });

    test('overflow at capacity drops the oldest entry', () {
      final buffer = InputBuffer<_Action>(window: 10, capacity: 2);
      buffer.record(_Action.attack);
      buffer.record(_Action.roll);
      buffer.record(_Action.parry); // Drops the attack; newest wins.

      expect(buffer.has(_Action.attack), isFalse);
      expect(buffer.consume(_Action.roll), isTrue);
      expect(buffer.consume(_Action.parry), isTrue);
    });

    test('advance on unscaled time keeps entries alive through a freeze', () {
      // Simulated hitstop: game-scaled dt is 0 for three frames while the
      // wall clock keeps running. The buffer only ever sees the wall dt, so
      // a roll pressed as the freeze lands is still live one frame after the
      // freeze ends (3 * 16ms + 16ms = 64ms < 150ms window)...
      final buffer = InputBuffer<_Action>(window: 0.15);
      buffer.record(_Action.roll);
      for (var frame = 0; frame < 3; frame++) {
        buffer.advance(0.016); // FrameTime.unscaledDelta; scaled delta is 0.
      }
      buffer.advance(0.016);
      expect(buffer.has(_Action.roll), isTrue);

      // ...and still expires on the wall clock, freeze or not.
      buffer.advance(0.15);
      expect(buffer.has(_Action.roll), isFalse);
    });

    test('clear discards everything buffered', () {
      final buffer = InputBuffer<_Action>(window: 10);
      buffer.record(_Action.attack);
      buffer.record(_Action.roll);
      buffer.clear();

      expect(buffer.has(_Action.attack), isFalse);
      expect(buffer.has(_Action.roll), isFalse);
      expect(buffer.consumeAny(<_Action>{_Action.attack, _Action.roll}),
          isNull);

      // The buffer stays usable after a clear.
      buffer.record(_Action.attack);
      expect(buffer.consume(_Action.attack), isTrue);
    });

    test('the ring survives wrap-around with interleaved record/consume', () {
      final buffer = InputBuffer<_Action>(window: 10, capacity: 3);
      // Push the head around the ring several times.
      for (var i = 0; i < 7; i++) {
        buffer.record(_Action.attack);
        expect(buffer.consume(_Action.attack), isTrue);
      }
      buffer.record(_Action.roll);
      buffer.record(_Action.attack);
      buffer.record(_Action.parry);

      expect(
        buffer.consumeAny(<_Action>{
          _Action.attack,
          _Action.roll,
          _Action.parry,
        }),
        _Action.roll,
      );
      expect(buffer.consume(_Action.parry), isTrue);
      expect(buffer.consume(_Action.attack), isTrue);
    });

    test('expired entries behind a live one do not block consume', () {
      final buffer = InputBuffer<_Action>(window: 0.1);
      buffer.record(_Action.attack);
      buffer.advance(0.2); // The attack is now stale.
      buffer.record(_Action.roll);

      expect(buffer.consume(_Action.attack), isFalse);
      expect(buffer.consume(_Action.roll), isTrue);
    });
  });
}
