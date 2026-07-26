/// Game state support.
library;

import '../schedule/schedule_label.dart';
import '../schedule/system_registration.dart';
import '../world/world.dart';

/// The active value of the state machine for [S].
///
/// Request changes through [NextState].
final class CurrentState<S extends Object> {
  CurrentState._(this._value);

  S _value;
  S? _previous;

  /// The active state value.
  S get value => _value;

  /// The value active before the most recent transition, or `null` before the
  /// first transition.
  S? get previous => _previous;
}

/// Where systems queue a transition for the state machine of [S].
final class NextState<S extends Object> {
  NextState._();

  S? _pending;

  /// Queues a transition to [value], applied at the next
  /// [App.applyStateTransitions] (the frame-start boundary under the standard
  /// driver). The last call before application wins; setting the value that is
  /// already current is a no-op (no exit/re-enter).
  void set(S value) => _pending = value;
}

/// A run condition that passes while the state machine for [S] is at [value].
///
/// ```dart
/// app.addSystem(movePlayerSystem,
///     schedule: Schedules.update, runIf: inState(GamePhase.overworld));
/// ```
RunCondition inState<S extends Object>(S value) =>
    (World world) => world.resources.get<CurrentState<S>>().value == value;

/// Despawns an entity when its state ends.
final class DespawnOnExit {
  /// The state value this entity lives under.
  final Object value;

  const DespawnOnExit(this.value);
}

/// A schedule that belongs to a state value's enter/exit lifecycle.
///
/// Unlike plain schedules, state schedules are created on demand when a system
/// is registered into them, and are run by the transition machinery rather
/// than the frame driver.
sealed class StateScheduleLabel extends ScheduleLabel {
  /// The state value this schedule is attached to.
  final Object value;

  StateScheduleLabel._(this.value, String id) : super(id);
}

/// The one-shot schedule run when the state machine transitions *to* [value]
/// (including the initial value during [App.start]).
final class OnEnter extends StateScheduleLabel {
  OnEnter(Object value) : super._(value, 'onEnter($value)');
}

/// The one-shot schedule run when the state machine transitions *away from*
/// [value].
final class OnExit extends StateScheduleLabel {
  OnExit(Object value) : super._(value, 'onExit($value)');
}

/// Type-erased view of one registered state machine, held by the app.
///
/// Not exported: user code interacts through [CurrentState]/[NextState].
abstract interface class StateMachine {
  /// The state type [S], for diagnostics.
  Type get stateType;

  /// Whether [value] belongs to this machine's state type.
  bool owns(Object value);

  /// Runs `OnEnter(initial)` through [runSchedule]. Called once from
  /// [App.start], after the startup schedule.
  void enterInitial(void Function(ScheduleLabel label) runSchedule);

  /// Applies a pending transition, if any: runs the old value's [OnExit],
  /// despawns entities scoped to it via [despawnScoped], swaps [CurrentState],
  /// then runs the new value's [OnEnter]. Returns whether a transition was
  /// applied.
  bool applyPending(
    void Function(ScheduleLabel label) runSchedule,
    void Function(Object oldValue) despawnScoped,
  );
}

/// The concrete machine created by `addState<S>`.
final class StateMachineRuntime<S extends Object> implements StateMachine {
  StateMachineRuntime(S initial)
    : current = CurrentState<S>._(initial),
      next = NextState<S>._();

  /// The resource pair inserted into the world at registration.
  final CurrentState<S> current;
  final NextState<S> next;

  @override
  Type get stateType => S;

  @override
  bool owns(Object value) => value is S;

  @override
  void enterInitial(void Function(ScheduleLabel label) runSchedule) =>
      runSchedule(OnEnter(current._value));

  @override
  bool applyPending(
    void Function(ScheduleLabel label) runSchedule,
    void Function(Object oldValue) despawnScoped,
  ) {
    final target = next._pending;
    if (target == null) return false;
    // Preserve transitions queued by lifecycle systems.
    next._pending = null;
    if (target == current._value) return false;
    final old = current._value;
    runSchedule(OnExit(old));
    despawnScoped(old);
    current
      .._previous = old
      .._value = target;
    runSchedule(OnEnter(target));
    return true;
  }
}
