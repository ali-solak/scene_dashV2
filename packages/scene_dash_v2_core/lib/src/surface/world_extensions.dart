/// Common [World] helpers.
library;

import '../entity/entity.dart';
import '../input/axis_input.dart';
import '../input/button_input.dart';
import '../input/input_buffer.dart';
import '../query/entity_query.dart';
import '../schedule/schedule_label.dart';
import '../schedule/schedule_runner.dart';
import '../state/despawn_after.dart';
import '../state/states.dart';
import '../time/fixed_time.dart';
import '../time/frame_time.dart';
import '../time/game_clock.dart';
import '../world/world.dart';
import 'game_builder.dart';
import 'observers.dart';
import 'remove_after.dart';
import 'spawning.dart';

extension WorldSurface on World {
  /// Sends [event] to its channel, registering the channel on first use.
  void emit<E extends Object>(E event) {
    if (E == event.runtimeType) registerEvent<E>();
    sendEvent(event);
  }

  /// Unread [E] events for the current system.
  ///
  /// Throws outside a running system.
  Iterable<E> events<E extends Object>() {
    final host = runningSystem;
    if (host is! EventCursorHost) {
      if (host is ObserverDispatch) {
        throw StateError(
          'world.events<$E>() called inside a component observer. Observers '
          'have no event-cursor registration: observers emit, systems read. '
          'Use world.emit here and consume the event in a system.',
        );
      }
      throw StateError(
        'world.events<$E>() called outside a running system. Event cursors '
        'are per-registration; read events inside a system registered with '
        'addSystem, or hold your own EventReader (advanced.dart).',
      );
    }
    return host.readerFor<E>(this).drain();
  }

  /// Consumes unread [E] events and reports whether any existed.
  bool consumeAny<E extends Object>() {
    var any = false;
    for (final _ in events<E>()) {
      any = true;
    }
    return any;
  }

  /// Runs the custom schedule [label] inline, to completion.
  ///
  /// A command boundary: spawns, adds, removals and despawns have settled
  /// when it returns. A queued [setState] has not — transitions stay with the
  /// frame. Call it between queries, never inside `.each`.
  void runSchedule(ScheduleLabel label) =>
      resources.get<ScheduleRunner>().run(label);

  /// Queues a state change.
  void setState<S extends Object>(S value) =>
      resources.get<NextState<S>>().set(value);

  /// The active value for state [S].
  S state<S extends Object>() => resources.get<CurrentState<S>>().value;

  /// The previous value for state [S].
  S? previousState<S extends Object>() =>
      resources.get<CurrentState<S>>().previous;

  /// Inserts or replaces [resource].
  void insert<T extends Object>(T resource) => resources.insert<T>(resource);

  /// Spawns an entity with [parts].
  ///
  /// [ownedBy] links its lifetime to another entity.
  Entity spawn(List<Object> parts, {Entity? ownedBy}) =>
      SpawnQueue.of(this).enqueue(parts, ownedBy: ownedBy);

  /// Queues despawning [entity], applied at the next command flush.
  void despawn(Entity entity) => commands.despawn(entity);

  /// Adds [component] to [entity] at the next command flush.
  ///
  /// [removeAfter] removes it after that many seconds of fixed game time.
  /// Adding it again without [removeAfter] cancels the deadline.
  void add(Entity entity, Object component, {double? removeAfter}) {
    SpawnQueue.of(this).addPart(entity, component);
    if (removeAfter != null) {
      RemoveAfterTracker.of(
        this,
      ).track(entity, component.runtimeType, removeAfter);
    } else {
      resources.tryGet<RemoveAfterTracker>()?.cancel(
        entity,
        component.runtimeType,
      );
    }
  }

  /// Removes [T] from [entity] at the next command flush.
  void remove<T>(Entity entity) {
    resources.tryGet<RemoveAfterTracker>()?.cancel(entity, T);
    commands.remove<T>(entity);
  }

  /// Time until [T] is removed from [entity].
  double? expiryOf<T>(Entity entity) {
    if (T == DespawnAfter) {
      final remaining = tryGet<DespawnAfter>(entity)?.remaining;
      return remaining == null || remaining > 0 ? remaining : 0;
    }
    return resources.tryGet<RemoveAfterTracker>()?.expiryOf(entity, T);
  }

  // Single components

  /// The only [T] in the world.
  T single<T extends Object>() {
    final store = SpawnQueue.of(this).ensureStore<T>();
    if (store.length != 1) {
      throw StateError(
        'world.single<$T>(): expected exactly one entity with $T, '
        'found ${store.length}.',
      );
    }
    return store.valueAt(0);
  }

  /// The only [T], or `null` when none exists.
  T? singleOrNull<T extends Object>() {
    final store = SpawnQueue.of(this).ensureStore<T>();
    if (store.length > 1) {
      throw StateError(
        'world.singleOrNull<$T>(): expected at most one entity with $T, '
        'found ${store.length}.',
      );
    }
    return store.length == 0 ? null : store.valueAt(0);
  }

  // Time

  /// Delta for the current schedule.
  double get dt => fixedContext
      ? resources.get<FixedTime>().delta
      : resources.get<FrameTime>().delta;

  /// This frame's clock-scaled delta, explicitly (see [dt]).
  double get delta => resources.get<FrameTime>().delta;

  /// The fixed timestep, explicitly (see [dt]).
  double get fixedDelta => resources.get<FixedTime>().delta;

  /// This frame's unscaled delta.
  double get unscaledDelta => resources.get<FrameTime>().unscaledDelta;

  /// The gameplay clock (pause, `timeScale`, `freezeFor` hitstop).
  GameClock get clock => resources.get<GameClock>();

  // Input

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

  // Entity filters

  /// Entities with every [require] type and no [exclude] type.
  EntityQuery entitiesWith({
    required List<Type> require,
    List<Type> exclude = const <Type>[],
  }) => queryEntities(withTypes: require, withoutTypes: exclude);
}
