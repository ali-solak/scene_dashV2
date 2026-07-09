/// A Bevy-style analog input resource keyed by an axis type [T].
///
/// Where [ButtonInput] models buttons (held or not), `AxisInput` models a
/// *continuous* value in `[-1, 1]` per axis — a thumbstick, a trigger, a
/// steering input. Widgets write it (`setValue`), systems read it (`value`). It
/// is the analog counterpart in Scene-Dash's level-state input story; discrete
/// intents are still events (see `Game.dispatch` / `EventReader`).
///
/// The split mirrors Bevy, which keeps `ButtonInput` and `Axis` as separate
/// resources: buttons and analog axes are genuinely different kinds of input, so
/// modelling a stick as a pair of booleans (or a button as a `0`/`1` axis) loses
/// information either way.
///
/// [T] is normally a small enum of axes:
///
/// ```dart
/// enum GameAxis { moveX, moveY }
///
/// // widget (analog thumbstick, already deadzoned & normalized):
/// input.setValue(GameAxis.moveX, -knob.dx);
///
/// // system — reads a double, so half-deflection is half speed for free:
/// final strafe = input.value(GameAxis.moveX);
/// ```
///
/// Systems that already multiply by an axis need no change to go analog: a value
/// of `0.4` simply yields proportional motion where `1.0` was full. Several
/// sources writing one axis (a stick *and* the arrow keys) is last-writer-wins;
/// a deadzone belongs in the widget, before `setValue`, so this stays a plain
/// value store.
///
/// Two axes compose a 2D stick for a character controller (`moveX`/`moveY`).
/// Each axis is clamped independently, so a stick that reports a *square* can
/// hand you `(1, 1)` — magnitude ~1.41, i.e. faster diagonal movement. Clamp the
/// *combined* vector to the unit disk in the consumer (or have the widget report
/// a disk), since a per-axis store cannot know the two form a plane.
final class AxisInput<T> {
  final Map<T, double> _values = <T, double>{};

  /// The current value of [axis] in `[-1, 1]`, or `0` when it was never set.
  double value(T axis) => _values[axis] ?? 0.0;

  /// Sets [axis] to [magnitude], clamped to `[-1, 1]`.
  void setValue(T axis, double magnitude) =>
      _values[axis] = magnitude.clamp(-1.0, 1.0).toDouble();

  /// Resets every axis to `0` (focus loss, disposal, a hard reset).
  void clear() => _values.clear();
}
