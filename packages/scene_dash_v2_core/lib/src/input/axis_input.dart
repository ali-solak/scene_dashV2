/// Analog input values, keyed by axis type [T].
///
/// Widgets write values with [setValue]; systems read them with [value]. Use
/// events for one-off actions such as firing or restarting.
///
/// ```dart
/// enum GameAxis { moveX, moveY }
///
/// input.setValue(GameAxis.moveX, -knob.dx);
/// final strafe = input.value(GameAxis.moveX);
/// ```
///
/// Each value is clamped independently. Clamp a combined two-axis movement
/// vector in the consumer if diagonal speed matters.
final class AxisInput<T> {
  final Map<T, double> _values = <T, double>{};

  /// The current value of [axis], or zero when it was never set.
  double value(T axis) => _values[axis] ?? 0.0;

  /// Sets [axis] to [magnitude], clamped to `[-1, 1]`.
  void setValue(T axis, double magnitude) =>
      _values[axis] = magnitude.clamp(-1.0, 1.0).toDouble();

  /// Resets every axis to zero.
  void clear() => _values.clear();
}
