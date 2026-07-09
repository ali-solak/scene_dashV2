import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

enum _Action { left, right, fire }

void main() {
  group('ButtonInput', () {
    test('press/release track held state', () {
      final input = ButtonInput<_Action>();
      expect(input.pressed(_Action.fire), isFalse);
      input.press(_Action.fire);
      expect(input.pressed(_Action.fire), isTrue);
      input.release(_Action.fire);
      expect(input.pressed(_Action.fire), isFalse);
    });

    test('press reports the released->held edge only once', () {
      final input = ButtonInput<_Action>();
      expect(input.press(_Action.fire), ButtonEdge.pressed);
      // Already held: idempotent, no edge (key-repeat / redundant source safe).
      expect(input.press(_Action.fire), ButtonEdge.none);
    });

    test('release reports the held->released edge only once', () {
      final input = ButtonInput<_Action>()..press(_Action.fire);
      expect(input.release(_Action.fire), ButtonEdge.released);
      expect(input.release(_Action.fire), ButtonEdge.none);
    });

    test('setPressed drives from a level source and returns the edge', () {
      final input = ButtonInput<_Action>();
      expect(input.setPressed(_Action.fire, true), ButtonEdge.pressed);
      expect(input.setPressed(_Action.fire, true), ButtonEdge.none);
      expect(input.setPressed(_Action.fire, false), ButtonEdge.released);
      expect(input.setPressed(_Action.fire, false), ButtonEdge.none);
    });

    test('axis is +1/-1/0 from two opposing actions', () {
      final input = ButtonInput<_Action>();
      expect(input.axis(_Action.left, _Action.right), 0);
      input.press(_Action.right);
      expect(input.axis(_Action.left, _Action.right), 1);
      input.press(_Action.left);
      expect(input.axis(_Action.left, _Action.right), 0, reason: 'both held');
      input.release(_Action.right);
      expect(input.axis(_Action.left, _Action.right), -1);
    });

    test('releaseAll clears every held action', () {
      final input = ButtonInput<_Action>()
        ..press(_Action.left)
        ..press(_Action.fire);
      expect(input.anyPressed, isTrue);
      input.releaseAll();
      expect(input.anyPressed, isFalse);
      expect(input.pressed(_Action.left), isFalse);
      expect(input.pressed(_Action.fire), isFalse);
    });

    test('a second source keeps the button held until both release', () {
      // Models two physical sources (key + touch) OR-combined by the caller.
      final input = ButtonInput<_Action>();
      var key = false;
      var touch = false;

      ButtonEdge sync() =>
          input.setPressed(_Action.fire, key || touch);

      key = true;
      expect(sync(), ButtonEdge.pressed);
      touch = true;
      expect(sync(), ButtonEdge.none, reason: 'already held');
      key = false; // releasing one source must not release the button
      expect(sync(), ButtonEdge.none);
      expect(input.pressed(_Action.fire), isTrue);
      touch = false;
      expect(sync(), ButtonEdge.released);
    });
  });
}
