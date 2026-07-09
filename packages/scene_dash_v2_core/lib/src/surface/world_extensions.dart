/// The v2 verbs on [World]: events, state sugar, resource insertion and
/// the structural verbs. What systems and features use; `Commands`,
/// `EventReader` and the state resources stay internal machinery.
library;

import '../entity/entity.dart';
import '../input/axis_input.dart';
import '../input/button_input.dart';
import '../input/input_buffer.dart';
import '../query/entity_query.dart';
import '../state/states.dart';
import '../time/fixed_time.dart';
import '../time/frame_time.dart';
import '../time/game_clock.dart';
import '../world/world.dart';
import 'game_builder.dart';
import 'spawning.dart';

/// The Part 1 world surface.
extension WorldSurface on World {
  /// Sends [event] to its channel, registering the channel on first use.
  ///
  /// Registration needs the static type [E]; when the call site widened
  /// the value ([E] differs from the runtime type) and no channel exists
  /// yet, the core `sendEvent` throws with its usual guidance.
  void emit<E extends Object>(E event) {
    if (E == event.runtimeType) registerEvent<E>();
    sendEvent(event);
  }

  /// Every [E] event this system has not seen yet, in emission order.
  ///
  /// Cursors are memoized per registration — the same system reading every
  /// frame never misses an event and never sees one twice, across the
  /// fixed-step loop included. The carried channel semantics (retention
  /// windows, multi-reader independence, lagging-reader diagnostics) apply
  /// unchanged. Throws outside a running system: cursors belong to
  /// registrations, so free-standing code holds its own `EventReader`
  /// (advanced tier) instead.
  Iterable<E> events<E extends Object>() {
    final host = runningSystem;
    if (host is! EventCursorHost) {
      throw StateError(
        'world.events<$E>() called outside a running system. Event cursors '
        'are per-registration; read events inside a system registered with '
        'addSystem, or hold your own EventReader (advanced.dart).',
      );
    }
    return host.readerFor<E>(this).drain();
  }

  /// Queues a transition for the state machine of [S] — sugar for
  /// `NextState<S>.set`; applied at the frame boundary.
  void setState<S extends Object>(S value) =>
      resources.get<NextState<S>>().set(value);

  /// The active value of the state machine for [S] — sugar for
  /// `CurrentState<S>.value`.
  S state<S extends Object>() => resources.get<CurrentState<S>>().value;

  /// Inserts (or replaces) the resource of type [T] — the feature-install
  /// shorthand for `resources.insert`.
  void insert<T extends Object>(T resource) => resources.insert<T>(resource);

  /// Reserves an entity now, applies [parts] (component values, tag
  /// instances) at the next command boundary, and returns the handle.
  /// Bundles are functions returning lists; composition is a spread.
  /// With [ownedBy], the new entity despawns automatically when its owner
  /// dies (see [OwnedBy]).
  Entity spawn(List<Object> parts, {Entity? ownedBy}) =>
      SpawnQueue.of(this).enqueue(parts, ownedBy: ownedBy);

  /// Queues despawning [entity], applied at the next command flush.
  void despawn(Entity entity) => commands.despawn(entity);

  /// Queues adding [component] to live [entity], applied at the next
  /// command boundary (D10). The component's runtime type must have a
  /// registered store by then (spawn a value of the type, query it, or
  /// `registerComponent<T>()` at install); parked otherwise, like a
  /// spawn-list part.
  void add(Entity entity, Object component) =>
      SpawnQueue.of(this).addPart(entity, component);

  /// Queues removing the component of type [T] from [entity], applied at
  /// the next command flush (D10).
  void remove<T>(Entity entity) => commands.remove<T>(entity);

  // ── time (D9) ─────────────────────────────────────────────────────────

  /// The delta you type: `FixedTime.delta` inside a fixed schedule,
  /// `FrameTime.delta` elsewhere — schedule-aware like `every()` (D7).
  double get dt => fixedContext
      ? resources.get<FixedTime>().delta
      : resources.get<FrameTime>().delta;

  /// This frame's clock-scaled delta, explicitly (see [dt]).
  double get delta => resources.get<FrameTime>().delta;

  /// The fixed timestep, explicitly (see [dt]).
  double get fixedDelta => resources.get<FixedTime>().delta;

  /// The gameplay clock (pause, `timeScale`, `freezeFor` hitstop).
  GameClock get clock => resources.get<GameClock>();

  // ── input helpers (D8) ────────────────────────────────────────────────

  /// The held-action resource for action type [A], created on first use.
  ButtonInput<A> buttons<A extends Object>() =>
      resources.getOrInsert<ButtonInput<A>>(ButtonInput<A>.new);

  /// The analog-axis resource for axis type [A], created on first use.
  AxisInput<A> axes<A extends Object>() =>
      resources.getOrInsert<AxisInput<A>>(AxisInput<A>.new);

  /// The buffered-intent resource for action type [A], created on first
  /// use with the default window.
  InputBuffer<A> buffer<A extends Object>() =>
      resources.getOrInsert<InputBuffer<A>>(InputBuffer<A>.new);

  // ── tag-only iteration ────────────────────────────────────────────────

  /// The entities carrying every type in [require] (tags or components)
  /// and none in [exclude] — v1's `EntityQuery`, for match sets with no
  /// component value to hand out. (Named `entitiesWith` because `entities`
  /// is the carried registry member.)
  EntityQuery entitiesWith({
    required List<Type> require,
    List<Type> exclude = const <Type>[],
  }) =>
      queryEntities(withTypes: require, withoutTypes: exclude);
}
