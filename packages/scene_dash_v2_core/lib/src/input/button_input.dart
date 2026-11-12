/// The transition a button crossed when its pressed state was updated.
enum ButtonEdge {
  /// The state did not change.
  none,

  /// Went from released to held.
  pressed,

  /// Went from held to released.
  released,

  canceled,
}

/// Held button state, keyed by action type [T].
///
/// Widgets call [press], [release], or [setPressed]. Systems use [pressed] and
/// [axis]. Use events for one-off actions.
final class ButtonInput<T> {
  final Set<T> _held = <T>{};
  final _EdgeLatch<T> _frame = _EdgeLatch<T>();
  final _EdgeLatch<T> _step = _EdgeLatch<T>();
  bool _inStep = false;

  /// Marks [action] held and returns the resulting edge.
  ButtonEdge press(T action) {
    if (!_held.add(action)) return ButtonEdge.none;
    _frame.pendingPressed.add(action);
    _step.pendingPressed.add(action);
    return ButtonEdge.pressed;
  }

  /// Marks [action] released and returns the resulting edge.
  ButtonEdge release(T action) {
    if (!_held.remove(action)) return ButtonEdge.none;
    _frame.pendingReleased.add(action);
    _step.pendingReleased.add(action);
    return ButtonEdge.released;
  }

  ButtonEdge cancel(T action) {
    if (!_held.remove(action)) return ButtonEdge.none;
    _frame.pendingPressed.remove(action);
    _step.pendingPressed.remove(action);
    return ButtonEdge.canceled;
  }

  bool justPressed(T action) =>
      (_inStep ? _step : _frame).pressed.contains(action);

  bool justReleased(T action) =>
      (_inStep ? _step : _frame).released.contains(action);

  void advanceFrame() => _frame.advance();

  void beginStep() {
    _step.advance();
    _inStep = true;
  }

  void endStep() => _inStep = false;

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
  void releaseAll() {
    _frame.pendingReleased.addAll(_held);
    _step.pendingReleased.addAll(_held);
    _held.clear();
  }
}

final class _EdgeLatch<T> {
  Set<T> pendingPressed = <T>{};
  Set<T> pendingReleased = <T>{};
  Set<T> pressed = <T>{};
  Set<T> released = <T>{};

  void advance() {
    if (pressed.isEmpty &&
        released.isEmpty &&
        pendingPressed.isEmpty &&
        pendingReleased.isEmpty) {
      return;
    }
    final spentPressed = pressed..clear();
    final spentReleased = released..clear();
    pressed = pendingPressed;
    released = pendingReleased;
    pendingPressed = spentPressed;
    pendingReleased = spentReleased;
  }
}
