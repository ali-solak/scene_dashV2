import '../commands/commands.dart';
import '../entity/entity.dart';
import '../entity/entity_registry.dart';
import '../events/event_channel.dart';
import '../query/entity_query.dart';
import '../query/query.dart';
import '../resources/resources.dart';
import '../storage/object_store.dart';
import '../storage/store_registry.dart';
import '../storage/tag_store.dart';

/// Stores entities, components, resources, and events.
final class World {
  /// Generational entity allocator.
  final EntityRegistry entities = EntityRegistry();

  /// Component-type to store mapping.
  final StoreRegistry stores = StoreRegistry();

  /// Singleton application resources.
  final Resources resources = Resources();

  /// Queues structural changes.
  late final Commands commands = Commands(this);

  final Map<Type, EventChannelMaintenance> _eventChannels =
      <Type, EventChannelMaintenance>{};

  // Keeps event updates allocation free.
  final List<Type> _eventTypes = <Type>[];
  final List<EventChannelMaintenance> _eventChannelList =
      <EventChannelMaintenance>[];

  /// Reports unread events removed by [updateEvents].
  void Function(Type eventType, int skippedEvents)? onEventReaderSkip;

  /// The system currently running.
  Object? runningSystem;

  /// Whether the current schedule uses fixed time.
  bool fixedContext = false;

  /// Number of queries currently iterating. Used by debug guards to detect
  /// structural mutation during active iteration.
  int _activeQueries = 0;

  /// Reports nested queries in debug mode.
  void Function(String message)? onNestedQuery;

  // Debug state for nested query reports.
  Query? _debugOuterQuery;
  Object? _debugOuterSystem;
  Set<Object>? _debugNestedReported;

  /// Current command flush depth.
  int _flushDepth = 0;

  /// Number of completed outer command flushes.
  int flushEpoch = 0;

  /// Marks entry into a command-boundary flush; pairs with [endFlush].
  void beginFlush() => _flushDepth++;

  /// Ends a command flush.
  void endFlush() {
    _flushDepth--;
    if (_flushDepth == 0) flushEpoch++;
  }

  /// Returns the store for [T], creating it when needed.
  ObjectComponentStore<T> ensureObjectStore<T>() => stores.ensureObject<T>();

  /// Returns the tag store for [T], creating it when needed.
  TagStore ensureTagStore<T>() => stores.ensureTag<T>();

  /// Registers an event channel for event type [T] if one does not yet exist.
  ///
  /// [retainedUpdates] controls how long unread events remain.
  /// Use `null` to keep them until every reader consumes them.
  void registerEvent<T>({int? retainedUpdates = 8}) {
    if (_eventChannels.containsKey(T)) return;
    final channel = EventChannel<T>(retainedUpdates: retainedUpdates);
    _eventChannels[T] = channel;
    _eventTypes.add(T);
    _eventChannelList.add(channel);
  }

  /// Sends [event] to its runtime type channel.
  ///
  /// Throws when the channel is not registered.
  void sendEvent(Object event) {
    final channel = _eventChannels[event.runtimeType];
    if (channel == null) {
      throw StateError(
        'No event channel registered for ${event.runtimeType}. A system must '
        'read EventReader<${event.runtimeType}> (or call addEvent<'
        '${event.runtimeType}>()) before events of that type can be sent.',
      );
    }
    channel.sendDynamic(event);
  }

  /// The event channel for event type [T]. Throws if it was never registered.
  EventChannel<T> eventChannel<T>() {
    final channel = _eventChannels[T];
    if (channel == null) {
      throw StateError(
        'No event channel registered for $T. Call addEvent<$T>() first.',
      );
    }
    return channel as EventChannel<T>;
  }

  /// Advances every event channel, reclaiming fully-consumed events and
  /// reporting readers that lost events to the retention window through
  /// [onEventReaderSkip].
  void updateEvents() {
    for (var i = 0; i < _eventChannelList.length; i++) {
      final skipped = _eventChannelList[i].update();
      if (skipped > 0) onEventReaderSkip?.call(_eventTypes[i], skipped);
    }
  }

  /// Event channels in registration order.
  Iterable<(Type, EventChannelMaintenance)> get debugEventChannels sync* {
    for (var i = 0; i < _eventChannelList.length; i++) {
      yield (_eventTypes[i], _eventChannelList[i]);
    }
  }

  /// Whether [entity] currently refers to a live entity.
  bool isAlive(Entity entity) => entities.isAlive(entity);

  /// Whether live [entity] currently has component or tag [T].
  bool has<T>(Entity entity) {
    if (!entities.isAlive(entity) || !stores.isRegistered(T)) return false;
    return stores.require(T).containsIndex(entity.index);
  }

  /// The component of type [T] on live [entity].
  ///
  /// Throws if the entity is stale, the component store is not registered, or
  /// the entity does not currently have [T].
  T get<T>(Entity entity) {
    if (!entities.isAlive(entity)) {
      throw StateError('Cannot get $T from stale entity $entity.');
    }
    final store = stores.object<T>();
    final value = store.valueOf(entity.index);
    if (value == null) {
      throw StateError('Entity $entity does not have component $T.');
    }
    return value;
  }

  /// The component of type [T] on [entity], or `null` if absent or stale.
  T? tryGet<T>(Entity entity) {
    if (!entities.isAlive(entity) || !stores.isRegistered(T)) return null;
    return stores.object<T>().valueOf(entity.index);
  }

  /// Returns [A] and [B], or `null` when either is missing.
  (A, B)? tryGet2<A, B>(Entity entity) {
    final a = tryGet<A>(entity);
    if (a == null) return null;
    final b = tryGet<B>(entity);
    if (b == null) return null;
    return (a, b);
  }

  /// [entity]'s [A], [B] and [C] as a record, or `null` unless *all three*
  /// are present. See [tryGet2].
  (A, B, C)? tryGet3<A, B, C>(Entity entity) {
    final a = tryGet<A>(entity);
    if (a == null) return null;
    final b = tryGet<B>(entity);
    if (b == null) return null;
    final c = tryGet<C>(entity);
    if (c == null) return null;
    return (a, b, c);
  }

  /// The resource of type [T].
  T resource<T extends Object>() => resources.get<T>();

  /// The resource of type [T], or `null` if none is registered.
  T? tryResource<T extends Object>() => resources.tryGet<T>();

  /// Whether a resource of type [T] is registered.
  bool hasResource<T extends Object>() => resources.contains<T>();

  /// Component and tag types on [entity].
  ///
  /// Returns an empty list for a stale entity.
  List<Type> debugComponentsOf(Entity entity) {
    if (!entities.isAlive(entity)) return const <Type>[];
    final index = entity.index;
    final result = <Type>[];
    for (final (type, store) in stores.entries) {
      if (store.containsIndex(index)) result.add(type);
    }
    return result;
  }

  /// Inserts or replaces component [component] (of type [T]) on [entity].
  void insertNow<T>(Entity entity, T component) =>
      insertNowByType(T, entity, component);

  /// Inserts a component using its runtime type.
  void insertNowByType(Type componentType, Entity entity, Object? component) {
    assert(
      _activeQueries == 0,
      'Structural mutation (insert) while a query is iterating.',
    );
    assert(
      entities.isAlive(entity),
      'Cannot insert $componentType on stale entity $entity.',
    );
    if (!entities.isAlive(entity)) return;
    stores.require(componentType).insertDynamic(entity.index, component);
  }

  /// Removes the component of type [T] from [entity], if present.
  void removeNow<T>(Entity entity) => removeNowByType(T, entity);

  /// Non-generic variant of [removeNow], keyed by a runtime [componentType].
  void removeNowByType(Type componentType, Entity entity) {
    assert(
      _activeQueries == 0,
      'Structural mutation (remove) while a query is iterating.',
    );
    assert(
      entities.isAlive(entity),
      'Cannot remove $componentType from stale entity $entity.',
    );
    if (!entities.isAlive(entity)) return;
    if (stores.isRegistered(componentType)) {
      stores.require(componentType).removeEntityIndex(entity.index);
    }
  }

  /// Despawns [entity], stripping it from every store first.
  void despawnNow(Entity entity) {
    assert(
      _activeQueries == 0,
      'Structural mutation (despawn) while a query is iterating.',
    );
    assert(entities.isAlive(entity), 'Cannot despawn stale entity $entity.');
    if (!entities.isAlive(entity)) return;
    final index = entity.index;
    for (final store in stores.all) {
      store.removeEntityIndex(index);
    }
    entities.despawn(entity);
  }

  /// Removes every entity and buffered event.
  ///
  /// Stores, channels, and readers stay registered.
  /// Resources remain unless [keepResources] is false.
  /// Call only when no query or command is active.
  void reset({bool keepResources = true}) {
    assert(_activeQueries == 0, 'World.reset() while a query is iterating.');
    assert(
      commands.isEmpty,
      'World.reset() with pending deferred commands: they would apply to '
      'despawned entities. Flush or drop them before resetting.',
    );
    for (final store in stores.all) {
      store.clear();
    }
    entities.despawnAll();
    for (var i = 0; i < _eventChannelList.length; i++) {
      _eventChannelList[i].clear();
    }
    if (!keepResources) resources.disposeAll();
  }

  /// Queries entities with every [withTypes] entry and no [withoutTypes] entry.
  EntityQuery queryEntities({
    required List<Type> withTypes,
    List<Type> withoutTypes = const <Type>[],
  }) {
    if (withTypes.isEmpty) {
      throw ArgumentError(
        'queryEntities needs at least one withTypes entry to drive iteration.',
      );
    }
    return EntityQuery(
      this,
      withTypes.map(stores.require).toList(growable: false),
      withoutTypes.map(stores.require).toList(growable: false),
    );
  }

  /// Begins query iteration (debug guard bookkeeping). Returns when iteration
  /// is allowed to proceed.
  void beginQuery([Query? query]) {
    assert(() {
      _debugNoteQueryBegin(query);
      return true;
    }());
    _activeQueries++;
  }

  /// Ends query iteration started by [beginQuery].
  void endQuery() {
    _activeQueries--;
    assert(() {
      if (_activeQueries == 0) {
        _debugOuterQuery = null;
        _debugOuterSystem = null;
      }
      return true;
    }());
  }

  /// Reports nested queries in the same system.
  void _debugNoteQueryBegin(Query? query) {
    final system = runningSystem;
    if (query == null || system == null) return;
    if (_activeQueries == 0) {
      _debugOuterQuery = query;
      _debugOuterSystem = system;
      return;
    }
    final outer = _debugOuterQuery;
    if (outer == null || !identical(_debugOuterSystem, system)) return;
    final reported = _debugNestedReported ??= Set.identity();
    if (!reported.add(system)) return;
    final sink = onNestedQuery;
    if (sink == null) return;
    final n = outer.debugRowEstimate;
    final m = query.debugRowEstimate;
    sink(
      'Nested query in ${_debugSystemName(system)}: ${query.debugLabel} '
      'iterated inside ${outer.debugLabel}.each — ~$n×$m comparisons per '
      'run. Hoist the inner query or restructure (see README query rules).',
    );
  }

  /// Returns a short system name for diagnostics.
  static String _debugSystemName(Object system) {
    final id = system.toString();
    final hash = id.lastIndexOf('#');
    var name = hash < 0 ? id : id.substring(hash + 1);
    final at = name.lastIndexOf('@');
    if (at > 0 && int.tryParse(name.substring(at + 1)) != null) {
      name = name.substring(0, at);
    }
    return name;
  }

  /// Whether any query is currently iterating.
  bool get isQueryActive => _activeQueries > 0;
}
