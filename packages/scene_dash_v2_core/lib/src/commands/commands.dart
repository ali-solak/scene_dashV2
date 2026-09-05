import '../entity/entity.dart';
import '../world/world.dart';
import 'bundle.dart';
import 'entity_commands.dart';

/// Queues structural world changes.
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
  static const int _opDeferred = 4;

  Commands(this._world);

  /// Whether there are no pending commands.
  bool get isEmpty => _ops.isEmpty;

  void _push(int op, Entity entity, Object? payload, Type type) {
    _ops.add(op);
    _entities.add(entity);
    _payloads.add(payload);
    _types.add(type);
  }

  /// Reserves an entity and queues [bundle].
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

  /// Queues [command] in the same FIFO as inserts, removals and despawns.
  ///
  /// Runs at a safe structural boundary. The callback owns stale-target
  /// handling, just like a [SceneDashBundle]. Used by surface commands that
  /// also need to manage parts waiting for a component store.
  void defer(Entity entity, void Function(World world, Entity entity) command) {
    _push(_opDeferred, entity, command, Object);
  }

  /// Queues removing the component of type [T] from [entity].
  void remove<T>(Entity entity) {
    _push(_opRemove, entity, null, T);
  }

  /// Queues removal using a runtime [componentType].
  void removeByType(Type componentType, Entity entity) {
    _push(_opRemove, entity, null, componentType);
  }

  /// Queues despawning [entity].
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
    _world.beginFlush();
    // Counted before the command runs, and dropped in the `finally`: a
    // command that throws is discarded with the ones before it, so a failed
    // flush cannot replay work the world has already taken.
    var consumed = 0;
    var passes = 0;
    try {
      // Include observer-enqueued commands, with a limit on successive
      // cascades rather than on the number of entities in a batch.
      while (consumed < _ops.length) {
        if (++passes > 64) {
          throw StateError('Deferred commands did not settle after 64 passes.');
        }
        final end = _ops.length;
        while (consumed < end) {
          final index = consumed++;
          final entity = _entities[index];
          switch (_ops[index]) {
            case _opInsert:
              _world.insertNowByType(_types[index], entity, _payloads[index]);
            case _opRemove:
              _world.removeNowByType(_types[index], entity);
            case _opDespawn:
              // A second despawn queued for the same entity finds it already
              // gone; skipping keeps deferred despawn idempotent (see [despawn]).
              if (_world.isAlive(entity)) _world.despawnNow(entity);
            case _opBundle:
              (_payloads[index] as SceneDashBundle).insertInto(_world, entity);
            case _opDeferred:
              (_payloads[index] as void Function(World, Entity))(
                _world,
                entity,
              );
          }
        }
      }
    } finally {
      _ops.removeRange(0, consumed);
      _entities.removeRange(0, consumed);
      _payloads.removeRange(0, consumed);
      _types.removeRange(0, consumed);
      _world.endFlush();
    }
  }
}
