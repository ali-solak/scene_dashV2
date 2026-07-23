/// The transition a button crossed when its pressed state was updated.
enum ButtonEdge {
  /// The state did not change.
  none,

  /// Went from released to held.
  pressed,

  /// Went from held to released.
  released,
}

/// Held button state, keyed by action type [T].
///
/// Widgets call [press], [release], or [setPressed]. Systems use [pressed] and
/// [axis]. Use events for one-off actions.
final class ButtonInput<T> {
  final Set<T> _held = <T>{};

  /// Marks [action] held and returns the resulting edge.
  ButtonEdge press(T action) =>
      _held.add(action) ? ButtonEdge.pressed : ButtonEdge.none;

  /// Marks [action] released and returns the resulting edge.
  ButtonEdge release(T action) =>
      _held.remove(action) ? ButtonEdge.released : ButtonEdge.none;

  /// Sets [action] from a level source and returns the resulting edge.
  ButtonEdge setPressed(T action, bool down) =>
      down ? press(action) : release(action);

  /// Whether [action] is currently held.
  bool pressed(T action) => _held.contains(action);

  /// A `-1 / 0 / +1` axis from two opposing actions.
  double axis(T negative, T positive) =>
      (pressed(positive) ? 1.0 : 0.0) - (pressed(negative) ? 1.0 : 0.0);

  /// Whether any action is currently held.
  bool get anyPressed => _held.isNotEmpty;

  /// Releases every held action.
  void releaseAll() => _held.clear();
}
