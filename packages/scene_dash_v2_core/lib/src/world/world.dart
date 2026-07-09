import '../commands/commands.dart';
import '../entity/entity.dart';
import '../entity/entity_registry.dart';
import '../events/event_channel.dart';
import '../query/entity_query.dart';
import '../resources/resources.dart';
import '../storage/object_store.dart';
import '../storage/store_registry.dart';
import '../storage/tag_store.dart';

/// The container for all ECS state: entities, component stores, resources and
/// event channels.
///
/// The world exposes *immediate* structural operations ([insertNow],
/// [removeNow], [despawnNow]) that mutate storage directly. Game code should
/// normally go through deferred `Commands` instead; the immediate variants are
/// what the command buffer and generated bundle adapters call once it is safe
/// to apply structural changes.
final class World {
  /// Generational entity allocator.
  final EntityRegistry entities = EntityRegistry();

  /// Component-type to store mapping.
  final StoreRegistry stores = StoreRegistry();

  /// Singleton application resources.
  final Resources resources = Resources();

  /// The shared deferred-command buffer for this world. Systems record
  /// structural changes here; the app flushes it after each schedule.
  late final Commands commands = Commands(this);

  final Map<Type, EventChannelMaintenance> _eventChannels =
      <Type, EventChannelMaintenance>{};

  // Parallel registration-order views of _eventChannels, so updateEvents can
  // iterate without allocating map entries each frame.
  final List<Type> _eventTypes = <Type>[];
  final List<EventChannelMaintenance> _eventChannelList =
      <EventChannelMaintenance>[];

  /// Called by [updateEvents] when a channel expired events past a lagging
  /// reader (see [EventChannel.retainedUpdates]): the event type and the
  /// largest number of unread events one reader lost this pass. Set by the
  /// app to surface a diagnostic.
  void Function(Type eventType, int skippedEvents)? onEventReaderSkip;

  /// The system currently executing, set by the function-system adapter for
  /// the duration of its run — what `world.events<T>()` resolves its
  /// per-registration cursor through, and what the debug access-drift check
  /// attributes query construction to. `null` between systems.
  ///
  /// v2 surface plumbing (see `docs/plan.md` task 5); the engine itself
  /// never reads it.
  Object? runningSystem;

  /// Whether execution is currently inside a fixed schedule — set around
  /// system bodies and their run conditions by the v2 surface, read by the
  /// schedule-aware `world.dt` and `every()` (D7/D9). `false` between
  /// systems and in frame-rate schedules.
  bool fixedContext = false;

  /// Number of queries currently iterating. Used by debug guards to detect
  /// structural mutation during active iteration.
  int _activeQueries = 0;

  /// Returns the object store for component type [T], registering a fresh one
  /// if none exists yet. Idempotent. Generated adapters and bundle inserts call
  /// this so component types are registered on first use.
  ObjectComponentStore<T> ensureObjectStore<T>() => stores.ensureObject<T>();

  /// Returns the tag store for tag type [T], registering a fresh one if none
  /// exists yet. Idempotent.
  TagStore ensureTagStore<T>() => stores.ensureTag<T>();

  /// Registers an event channel for event type [T] if one does not yet exist.
  ///
  /// [retainedUpdates] bounds how many maintenance passes an unread event
  /// survives (see [EventChannel.retainedUpdates]); `null` retains events until
  /// every reader has consumed them. Ignored if the channel already exists.
  void registerEvent<T>({int? retainedUpdates = 2}) {
    if (_eventChannels.containsKey(T)) return;
    final channel = EventChannel<T>(retainedUpdates: retainedUpdates);
    _eventChannels[T] = channel;
    _eventTypes.add(T);
    _eventChannelList.add(channel);
  }

  /// Sends [event] to the channel for its **runtime** type.
  ///
  /// Routing by `event.runtimeType` (rather than a static type argument) is what
  /// makes `Game.dispatch` robust: a `cond ? A() : B()` argument is statically
  /// typed as the common supertype of `A` and `B`, so a `send<T>`-style API would
  /// infer `T` as that supertype and silently deliver to a channel no system
  /// reads. The concrete instance always knows its own type, so this always hits
  /// the right channel.
  ///
  /// Throws if no channel is registered for the runtime type — register it by
  /// reading `EventReader<T>` in a system, or with `addEvent<T>()`.
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

  /// [entity]'s [A] and [B] as a record, or `null` unless *both* are present —
  /// [tryGet] composed over two components, sharing its null conditions
  /// (stale entity, unregistered store, missing component).
  ///
  /// For one-off multi-component reads outside a query (event handlers,
  /// setup code). The record fields are the live components, so mutating
  /// their fields writes through. Cold-path convenience: allocates a record;
  /// per-frame loops should use a cached query's `get` instead.
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

  /// Every registered component and tag type live [entity] currently carries,
  /// in store-registration order; empty for a stale handle.
  ///
  /// Debug surface — the answer to "what *is* this entity?" in a log or a
  /// test failure. Scans every registered store and allocates the list, so
  /// keep it out of per-frame release code; `debugDescribe` renders the same
  /// information as one line.
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

  /// Non-generic variant of [insertNow], keyed by a runtime [componentType].
  ///
  /// Used by the deferred command buffer, which records the component type per
  /// command instead of capturing it in a closure.
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

  /// Despawns everything and clears all buffered events, returning the world
  /// to an empty-but-wired state: stores, event channels, registered readers
  /// and (by default) resources all stay registered, only their contents go.
  ///
  /// The "restart the run" primitive — new game, back to title, retry from
  /// checkpoint — replacing hand-written despawn-the-world systems:
  ///
  /// * every store is emptied ([ComponentStore.clear]), which bumps its
  ///   revision — that is what lets the `flutter_scene` mount adapter detach
  ///   every auto-mounted node on its next run, so no manual scene cleanup is
  ///   needed;
  /// * every live entity is despawned with a generation bump
  ///   ([EntityRegistry.despawnAll]), so handles held across the reset
  ///   reject instead of addressing respawned entities;
  /// * every event channel is cleared ([EventChannel.clear]); readers stay
  ///   registered and simply see nothing until new events arrive.
  ///
  /// [keepResources] (the default) preserves all resources — timers, input,
  /// clocks, and the `CurrentState`/`NextState` machines keep running, so a
  /// game wanting a state reset queues a `NextState` transition after the
  /// call. Pass `false` to also drop every resource; only do that when
  /// re-initialization follows, since initialized systems keep their resolved
  /// resource references.
  ///
  /// Must not be called while a query is iterating, and asserts that no
  /// deferred commands are pending — resetting with queued structural changes
  /// is a bug (they would apply to despawned entities), so it fails loudly.
  /// Call it from a safe boundary such as an `OnEnter` system's body after
  /// its schedule's commands flushed, or between frames.
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
    if (!keepResources) resources.clear();
  }

  /// Creates an entity-only query over the entities carrying every type in
  /// [withTypes] (tags or components) and none in [withoutTypes]. For match
  /// sets defined entirely by tags, where there is no component value to hand
  /// out; [withTypes] must not be empty — it drives the iteration.
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

  // v2: the classic query1..query4 conveniences moved verbatim to the
  // ClassicWorldQueries extension (src/query/world_queries.dart) so the
  // record-query surface can own the query2/3/4 names — Dart instance
  // members always win over extensions. Call sites are source-compatible.

  /// Begins query iteration (debug guard bookkeeping). Returns when iteration
  /// is allowed to proceed.
  void beginQuery() => _activeQueries++;

  /// Ends query iteration started by [beginQuery].
  void endQuery() => _activeQueries--;

  /// Whether any query is currently iterating.
  bool get isQueryActive => _activeQueries > 0;
}
