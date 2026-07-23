/// A small state machine with one-tick transition edges.
library;

/// Stores the current state, time in state, and transition edges.
///
/// Call [tick] before transition logic. A transition remains visible until the
/// next tick, so later systems can read it in the same frame.
final class Machine<S> {
  S _state;
  S _exited;
  double _elapsed = 0;
  bool _entered = false;
  bool _left = false;

  Machine(S initial) : _state = initial, _exited = initial;

  /// The current state.
  S get state => _state;

  /// Seconds spent in the current state. [go] resets it.
  double get elapsed => _elapsed;

  /// Clears transition edges and advances time in the current state.
  void tick(double dt) {
    _entered = false;
    _left = false;
    _elapsed += dt;
  }

  /// Transitions to [next]. A same-state call does nothing.
  void go(S next) {
    if (next == _state) return;
    _exited = _state;
    _state = next;
    _elapsed = 0;
    _entered = true;
    _left = true;
  }

  /// Whether the machine entered [s] this tick.
  bool justEntered(S s) => _entered && s == _state;

  /// Whether the machine left [s] this tick.
  bool justExited(S s) => _left && s == _exited;

  /// A compact state and elapsed-time label for diagnostics.
  @override
  String toString() {
    final raw = '$_state';
    final dot = raw.indexOf('.');
    final label = dot >= 0 ? raw.substring(dot + 1) : raw;
    return '$label (${_elapsed.toStringAsFixed(2)}s)';
  }
}
