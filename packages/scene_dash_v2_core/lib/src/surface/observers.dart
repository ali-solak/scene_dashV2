/// Component observers: typed `onAdd`/`onRemove` callbacks fired during the
/// command-boundary flush, immediately after the individual change applies
/// (S1). Registration is explicit and per feature through
/// `GameBuilder.observe<T>`; this file is the registry underneath.
library;

import '../entity/entity.dart';
import '../storage/component_store.dart';
import '../world/world.dart';
import 'tag.dart';

/// An observer callback: the world (post-change), the entity, and the
/// component instance — for `onRemove`, the still-live removed instance.
typedef ComponentObserver<T> =
    void Function(World world, Entity entity, T component);

/// The value [World.runningSystem] holds while observer callbacks run.
///
/// Observers have no event-cursor registration, so `world.events<T>()`
/// recognizes this marker and throws with the rule spelled out: observers
/// emit, systems read.
final class ObserverDispatch {
  const ObserverDispatch._();

  /// The single marker instance.
  static const ObserverDispatch marker = ObserverDispatch._();
}

/// Per-world observer registration lists, attached to the store seams.
///
/// Carried as a resource (created on first `observe`); unobserved component
/// types keep `null` store hooks and pay nothing. Callbacks fire in
/// registration order, with [World.runningSystem] set to
/// [ObserverDispatch.marker] for the duration.
final class ObserverRegistry {
  /// The world whose stores this registry is attached to.
  final World world;

  final Map<Type, _TypeObservers> _byType = <Type, _TypeObservers>{};

  // Debug cascade guard (S6): per-type firing counts within one outermost
  // flush, reset lazily when the world's flush epoch advances.
  final Map<Type, int> _fireCounts = <Type, int>{};
  int _guardEpoch = -1;
  static const int _cascadeLimit = 16;

  ObserverRegistry._(this.world);

  /// The world's registry, created on first use.
  static ObserverRegistry of(World world) => world.resources
      .getOrInsert<ObserverRegistry>(() => ObserverRegistry._(world));

  /// Registers [onAdd]/[onRemove] for component type [T]; see
  /// `GameBuilder.observe` for the authoring-surface contract. Registering
  /// is also a typed site: the store for [T] is created if it does not
  /// exist yet (a tag store when [T] implements `Tag`).
  void observe<T extends Object>({
    ComponentObserver<T>? onAdd,
    ComponentObserver<T>? onRemove,
  }) {
    if (onAdd == null && onRemove == null) {
      throw ArgumentError(
        'observe<$T>() needs at least one of onAdd:/onRemove:.',
      );
    }
    final store = _storeFor<T>();
    final entry = _byType.putIfAbsent(T, _TypeObservers.new);
    if (onAdd != null) {
      entry.onAdd.add(
        (world, entity, value) => onAdd(world, entity, value as T),
      );
    }
    if (onRemove != null) {
      entry.onRemove.add(
        (world, entity, value) => onRemove(world, entity, value as T),
      );
    }
    store.onAdded ??= (index, payload) => _fire(T, entry.onAdd, index, payload);
    store.onRemoved ??= (index, payload) =>
        _fire(T, entry.onRemove, index, payload);
  }

  ComponentStore _storeFor<T extends Object>() {
    if (world.stores.isRegistered(T)) return world.stores.require(T);
    // A tag type's store cannot be created from an instance, so decide by
    // the static type: List<T> is covariant, making this a subtype test.
    return <T>[] is List<Tag>
        ? world.ensureTagStore<T>()
        : world.ensureObjectStore<T>();
  }

  void _fire(
    Type type,
    List<ComponentObserver<Object>> observers,
    int entityIndex,
    Object? payload,
  ) {
    if (observers.isEmpty) return;
    if (payload == null) {
      // Only reachable for a tag added through the payload-free machinery
      // path before any instance passed through the store.
      throw StateError(
        'observe<$type> fired but no $type instance has ever passed through '
        'its store (the tag was added via the machinery TagStore.add). Add '
        'tags through spawn lists or world.add so observers receive an '
        'instance.',
      );
    }
    assert(() {
      if (_guardEpoch != world.flushEpoch) {
        _guardEpoch = world.flushEpoch;
        _fireCounts.clear();
      }
      final count = (_fireCounts[type] ?? 0) + 1;
      _fireCounts[type] = count;
      if (count > _cascadeLimit) {
        throw StateError(
          'Observers for $type fired $count times within one command flush '
          '— an observer is re-adding or re-removing what it observes, '
          'looping the flush (S6). Break the cycle: react to the change, '
          'do not undo-and-redo it.',
        );
      }
      return true;
    }());
    final entity = world.entities.resolve(entityIndex);
    final previous = world.runningSystem;
    world.runningSystem = ObserverDispatch.marker;
    try {
      for (var i = 0; i < observers.length; i++) {
        observers[i](world, entity, payload);
      }
    } finally {
      world.runningSystem = previous;
    }
  }
}

final class _TypeObservers {
  final List<ComponentObserver<Object>> onAdd = <ComponentObserver<Object>>[];
  final List<ComponentObserver<Object>> onRemove =
      <ComponentObserver<Object>>[];
}
