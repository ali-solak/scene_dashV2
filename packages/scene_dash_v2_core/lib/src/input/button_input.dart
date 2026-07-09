/// The transition a button crossed when its pressed state was updated.
enum ButtonEdge {
  /// The state did not change (already held, or already released).
  none,

  /// Went from released to held this update.
  pressed,

  /// Went from held to released this update.
  released,
}

/// A Bevy-style level-state input resource keyed by an action type [T].
///
/// [ButtonInput] tracks which actions are *currently held*. It is the resource
/// half of Scene-Dash's input story: Flutter widgets and keyboard handlers write
/// it (`press`/`release`/`setPressed`) and systems read it (`pressed`/`axis`).
/// It answers the *continuous* questions — "is fire held?", "what is the strafe
/// axis?" — and is deliberately allocation-free per frame.
///
/// Discrete, once-consumed intents (a shot fired on release, a restart request)
/// are *not* modelled here — those are events, sent with `Game.dispatch` and read
/// with `EventReader`, so they are delivered exactly once and never leak across
/// the fixed-step loop. Level state here, edges as events: that split is what
/// keeps widget↔system wiring thin.
///
/// [T] is normally a small enum of game actions:
///
/// ```dart
/// enum GameAction { left, right, fire }
///
/// // widget / key handler:
/// input.setPressed(GameAction.left, isLeftDown);
///
/// // system:
/// final strafe = input.axis(GameAction.left, GameAction.right); // -1, 0, or +1
/// if (input.pressed(GameAction.fire)) { /* charging */ }
/// ```
///
/// Two physical sources mapping to one action (a key *and* an on-screen button)
/// should be OR-combined by the caller before `setPressed`, so the button is held
/// while *either* source is down and releasing one never cancels the other.
final class ButtonInput<T> {
  final Set<T> _held = <T>{};

  /// Marks [action] held. Returns [ButtonEdge.pressed] only on the
  /// released→held transition (idempotent while already held, so key-repeat and
  /// redundant sources are safe).
  ButtonEdge press(T action) =>
      _held.add(action) ? ButtonEdge.pressed : ButtonEdge.none;

  /// Marks [action] released. Returns [ButtonEdge.released] only on the
  /// held→released transition.
  ButtonEdge release(T action) =>
      _held.remove(action) ? ButtonEdge.released : ButtonEdge.none;

  /// Drives [action] from a level source: presses when [down], releases
  /// otherwise. Returns the edge crossed, if any — the caller can dispatch a
  /// press/release *event* on a non-[ButtonEdge.none] result.
  ButtonEdge setPressed(T action, bool down) =>
      down ? press(action) : release(action);

  /// Whether [action] is currently held.
  bool pressed(T action) => _held.contains(action);

  /// A `-1 / 0 / +1` axis from two opposing actions: `+1` when only [positive]
  /// is held, `-1` when only [negative] is held, `0` when both or neither are.
  double axis(T negative, T positive) =>
      (pressed(positive) ? 1.0 : 0.0) - (pressed(negative) ? 1.0 : 0.0);

  /// Whether any action is currently held.
  bool get anyPressed => _held.isNotEmpty;

  /// Releases every held action (focus loss, disposal, a hard reset). Edges are
  /// not reported — callers that need to dispatch cancel events should read the
  /// relevant `pressed` states before calling this.
  void releaseAll() => _held.clear();
}
