import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

enum _Axis { moveX, moveY }

void main() {
  group('AxisInput', () {
    test('an unset axis reads as zero', () {
      expect(AxisInput<_Axis>().value(_Axis.moveX), 0);
    });

    test('setValue stores an independent value per axis', () {
      final input = AxisInput<_Axis>()
        ..setValue(_Axis.moveX, 0.4)
        ..setValue(_Axis.moveY, -0.7);
      expect(input.value(_Axis.moveX), closeTo(0.4, 1e-9));
      expect(input.value(_Axis.moveY), closeTo(-0.7, 1e-9));
    });

    test('setValue clamps to [-1, 1]', () {
      final input = AxisInput<_Axis>()..setValue(_Axis.moveX, 2.5);
      expect(input.value(_Axis.moveX), 1.0);
      input.setValue(_Axis.moveX, -3.0);
      expect(input.value(_Axis.moveX), -1.0);
    });

    test('the last writer wins for a shared axis', () {
      // A stick and the keyboard both drive moveX; whoever wrote last is read.
      final input = AxisInput<_Axis>()
        ..setValue(_Axis.moveX, 1.0) // keyboard: full right
        ..setValue(_Axis.moveX, 0.3); // stick: partial
      expect(input.value(_Axis.moveX), closeTo(0.3, 1e-9));
    });

    test('clear zeroes every axis', () {
      final input = AxisInput<_Axis>()
        ..setValue(_Axis.moveX, 1)
        ..setValue(_Axis.moveY, 1)
        ..clear();
      expect(input.value(_Axis.moveX), 0);
      expect(input.value(_Axis.moveY), 0);
    });
  });
}
