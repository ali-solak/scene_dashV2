import '../entity/entity.dart';
import '../world/world.dart';
import 'bundle.dart';
import 'entity_commands.dart';

/// Records deferred structural changes to be applied at a safe boundary.
///
/// Field writes through query references are immediate, but structural changes
/// (spawning, inserting/removing components, despawning) are deferred and
/// applied once the current schedule finishes, so sparse-set swap removal can
/// never invalidate a query that is still iterating.
///
/// Entity *allocation* is the one exception: [spawn] reserves a live entity
/// immediately so callers get a usable handle, while the component insertions
/// for that entity are deferred like everything else.
///
/// Commands are recorded as typed rows in parallel lists (an op tag, the
/// target entity, an optional payload and component type), not as closures, so
/// enqueueing a command performs no per-command allocation once the lists have
/// grown to a frame's working size.
final class Commands {
  final World _world;

  // One recorded command = one row across these parallel lists. The lists are
  // cleared after every flush but keep their capacity.
  final List<int> _ops = <int>[];
  final List<Entity> _entities = <Entity>[];
  final List<Object?> _payloads = <Object?>[];
  final List<Type> _types = <Type>[];

  static const int _opInsert = 0;
  static const int _opRemove = 1;
  static const int _opDespawn = 2;
  static const int _opBundle = 3;

  Commands(this._world);

  /// Whether there are no pending commands.
  bool get isEmpty => _ops.isEmpty;

  void _push(int op, Entity entity, Object? payload, Type type) {
    _ops.add(op);
    _entities.add(entity);
    _payloads.add(payload);
    _types.add(type);
  }

  /// Reserves a new entity immediately and returns fluent commands targeting
  /// it, so a spawn can be decorated in place:
  ///
  /// ```dart
  /// commands.spawn(BossBundle())
  ///   ..insert(const DespawnOnExit(GamePhase.dungeon));
  /// final rock = commands.spawn(RockBundle()).entity;
  /// ```
  ///
  /// If [bundle] is given, its component insertions are queued and applied on
  /// the next [apply] (so the entity exists right away but is populated at a
  /// safe boundary). Inserts chained on the returned [EntityCommands] apply in
  /// the same flush, after the bundle's own components.
  EntityCommands spawn([SceneDashBundle? bundle]) {
    final entity = _world.entities.spawn();
    if (bundle != null) {
      _push(_opBundle, entity, bundle, Object);
    }
    return EntityCommands(this, entity);
  }

  /// Returns a fluent command handle targeting [entity].
  EntityCommands entity(Entity entity) => EntityCommands(this, entity);

  /// Queues inserting [component] of type [T] onto [entity].
  void insert<T>(Entity entity, T component) {
    _push(_opInsert, entity, component, T);
  }

  /// Queues removing the component of type [T] from [entity].
  void remove<T>(Entity entity) {
    _push(_opRemove, entity, null, T);
  }

  /// Queues despawning [entity].
  ///
  /// Idempotent at the flush: an entity already despawned by an earlier
  /// command in the same [apply] is skipped, so independent systems — a
  /// lifetime expiring the same frame a projectile hits something, say —
  /// can each queue the despawn without coordinating.
  void despawn(Entity entity) {
    _push(_opDespawn, entity, null, Object);
  }

  /// Applies and clears all pending commands. Must not be called while a query
  /// is iterating.
  void apply() {
    assert(
      !_world.isQueryActive,
      'Commands.apply() called while a query is iterating.',
    );
    if (_ops.isEmpty) return;
    // Iterate by index: a command may enqueue follow-up commands, which should
    // also be applied in this flush.
    for (var i = 0; i < _ops.length; i++) {
      final entity = _entities[i];
      switch (_ops[i]) {
        case _opInsert:
          _world.insertNowByType(_types[i], entity, _payloads[i]);
        case _opRemove:
          _world.removeNowByType(_types[i], entity);
        case _opDespawn:
          // A second despawn queued for the same entity finds it already
          // gone; skipping keeps deferred despawn idempotent (see [despawn]).
          if (_world.isAlive(entity)) _world.despawnNow(entity);
        case _opBundle:
          (_payloads[i] as SceneDashBundle).insertInto(_world, entity);
      }
    }
    _ops.clear();
    _entities.clear();
    _payloads.clear();
    _types.clear();
  }
}
