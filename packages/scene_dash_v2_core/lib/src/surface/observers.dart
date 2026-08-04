/// Component add and remove observers.
library;

import '../entity/entity.dart';
import '../storage/component_store.dart';
import '../world/world.dart';
import 'tag.dart';

/// Runs after a component is added or removed.
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

/// Stores observers for one world.
final class ObserverRegistry {
  /// The world whose stores this registry is attached to.
  final World world;

  final Map<Type, _TypeObservers> _byType = <Type, _TypeObservers>{};

  // Detect observer loops in debug mode.
  final Map<Type, Map<int, int>> _fireCounts = <Type, Map<int, int>>{};
  int _guardEpoch = -1;
  static const int _cascadeLimit = 16;

  /// Creates the registry owned by [world].
  ObserverRegistry(this.world);

  /// The registry owned by [world].
  static ObserverRegistry of(World world) => world.observers;

  /// Removes every registered callback while retaining the store hooks.
  ///
  /// Keeping the per-type entries lets observers registered after a nuclear
  /// world reset reuse the hooks already attached to component stores.
  void clear() {
    for (final entry in _byType.values) {
      entry.onAdd.clear();
      entry.onRemove.clear();
    }
    _fireCounts.clear();
    _guardEpoch = -1;
  }

  /// Registers add and remove callbacks for [T].
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
      final perEntity = _fireCounts.putIfAbsent(type, () => <int, int>{});
      final count = (perEntity[entityIndex] ?? 0) + 1;
      perEntity[entityIndex] = count;
      if (count > _cascadeLimit) {
        throw StateError(
          'Observers for $type fired $count times for one entity within '
          'one command flush — an observer is re-adding or re-removing '
          'what it observes, looping the flush (S6). Break the cycle: '
          'react to the change, do not undo-and-redo it.',
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
