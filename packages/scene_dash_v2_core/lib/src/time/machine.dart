/// `GameTimer`'s sibling for *modes*: a value-type state machine whose
/// transition edges follow the `justFinished` convention — true for
/// exactly one tick-window, read by systems, never delivered by callback.
library;

/// A mode machine for components: the current state, seconds in it, and
/// one-tick-window transition edges.
///
/// A plain value type, in the same family as `GameTimer`: machines are
/// fields on components, never registered anywhere, and the owner system
/// ticks them with `world.dt` — so they pause, slow and freeze with the
/// game exactly like a timer, and determinism follows from the owner's
/// ordering with nothing new to schedule. No callbacks: the component
/// computes, the system performs world effects — the machine exposes
/// edges, and systems spawn, emit and mutate on them.
///
/// ```dart
/// final class AttackState {
///   final phase = Machine<CombatPhase>(CombatPhase.idle);
/// }
///
/// // The owner system, each fixed step: tick first, then transition.
/// attack.phase.tick(world.dt);
/// switch (attack.phase.state) {
///   case CombatPhase.startup when attack.phase.elapsed >= startupSeconds:
///     attack.phase.go(CombatPhase.active);
///   // ...
/// }
///
/// // Any later system, same frame:
/// if (attack.phase.justEntered(CombatPhase.active)) openHitbox(world);
/// ```
///
/// **The edge latch.** [go] raises the entry edge for the new state (and
/// the exit edge for the state left) immediately; a [tick] lowers any
/// edge raised before it, then accumulates. An edge is therefore true for
/// exactly one tick-window: a transition made inside the owner's switch —
/// after its own tick — stays visible to every later system this frame,
/// and to the owner itself until its next tick. Several [go]s inside one
/// window leave the final state's entry edge and the *last* exit;
/// intermediate edges are not tracked. A same-state [go] is fully inert:
/// no edges, and [elapsed] keeps accumulating.
final class Machine<S> {
  S _state;
  S _exited;
  double _elapsed = 0;
  bool _entered = false;
  bool _left = false;

  Machine(S initial)
      : _state = initial,
        _exited = initial;

  /// The current state.
  S get state => _state;

  /// Seconds spent in the current state — scaled game time under the
  /// `world.dt` convention, so pause, slow motion and hitstop stretch it.
  /// [go] zeroes it.
  double get elapsed => _elapsed;

  /// Advances the machine by [dt]: lowers any edge raised before this
  /// tick, then adds [dt] to [elapsed]. The owner calls this once per
  /// run, before its transition logic.
  void tick(double dt) {
    _entered = false;
    _left = false;
    _elapsed += dt;
  }

  /// Transitions to [next]: zeroes [elapsed], raises the entry edge for
  /// [next] and the exit edge for the state left. A same-state call is a
  /// no-op.
  void go(S next) {
    if (next == _state) return;
    _exited = _state;
    _state = next;
    _elapsed = 0;
    _entered = true;
    _left = true;
  }

  /// Whether the machine entered [s] in the current tick-window.
  bool justEntered(S s) => _entered && s == _state;

  /// Whether the machine left [s] in the current tick-window; [s] is
  /// compared against the state most recently left.
  bool justExited(S s) => _left && s == _exited;

  /// `'charging (0.42s)'` — the state (an enum value's name; other types
  /// render their own `toString`) and the time in it, for logs and
  /// `debugDescribe`.
  @override
  String toString() {
    final raw = '$_state';
    final dot = raw.indexOf('.');
    final label = dot >= 0 ? raw.substring(dot + 1) : raw;
    return '$label (${_elapsed.toStringAsFixed(2)}s)';
  }
}
