/// Deferred entity spawning.
library;

import '../diagnostics/name.dart';
import '../entity/entity.dart';
import '../events/event_channel.dart';
import '../state/despawn_after.dart';
import '../state/states.dart';
import '../storage/object_store.dart';
import '../time/frame_time.dart';
import '../world/world.dart';
import 'tag.dart';

/// Despawns this entity when [owner] dies.
final class OwnedBy {
  /// The entity whose death despawns this one.
  final Entity owner;

  const OwnedBy(this.owner);
}

/// Stores pending spawns for one world.
final class SpawnQueue {
  /// The world this queue spawns into.
  final World world;

  /// Where the aged-parked-part diagnostic goes; wired by the game shell.
  void Function(String message)? onDiagnostic;

  final List<_PendingSpawn> _pending = <_PendingSpawn>[];
  final Map<Entity, List<Object>> _parked = <Entity, List<Object>>{};
  final Map<Entity, int> _parkedAtFrame = <Entity, int>{};
  final Set<Type> _reportedParkedTypes = <Type>{};
  final ObjectComponentStore<OwnedBy> _owned;

  SpawnQueue._(this.world) : _owned = world.ensureObjectStore<OwnedBy>() {
    world
      ..ensureObjectStore<Name>()
      ..ensureObjectStore<DespawnAfter>()
      ..ensureObjectStore<DespawnOnExit>();
  }

  /// The world's queue, created on first use.
  static SpawnQueue of(World world) =>
      world.resources.getOrInsert<SpawnQueue>(() => SpawnQueue._(world));

  /// Reserves an entity now and queues [parts] for the next [flush].
  Entity enqueue(List<Object> parts, {Entity? ownedBy}) {
    final entity = world.entities.spawn();
    _pending.add(_PendingSpawn(entity, parts, ownedBy));
    return entity;
  }

  /// Adds [part] to [entity] during the next [flush].
  void addPart(Entity entity, Object part) {
    _pending.add(_PendingSpawn(entity, <Object>[part], null));
  }

  /// Creates the store for [T] and inserts waiting parts.
  ObjectComponentStore<T> ensureStore<T extends Object>() {
    final store = world.ensureObjectStore<T>();
    if (_parked.isNotEmpty) _claimParked<T>();
    return store;
  }

  void _claimParked<T extends Object>() {
    List<Entity>? emptied;
    for (final entry in _parked.entries) {
      final entity = entry.key;
      if (!world.isAlive(entity)) {
        (emptied ??= <Entity>[]).add(entity);
        continue;
      }
      entry.value.removeWhere((part) {
        if (part is! T) return false;
        world.insertNow<T>(entity, part);
        return true;
      });
      if (entry.value.isEmpty) (emptied ??= <Entity>[]).add(entity);
    }
    if (emptied != null) {
      for (final entity in emptied) {
        _parked.remove(entity);
        _parkedAtFrame.remove(entity);
      }
    }
  }

  /// Applies pending spawns and owned despawns.
  void flush() {
    world.beginFlush();
    try {
      var passes = 0;
      do {
        world.commands.apply();
        _applyPending();
        passes++;
        if (passes > 64) {
          throw StateError(
            'Spawns and owned despawns did not settle after 64 passes.',
          );
        }
      } while (_sweepOwnedOnce() ||
          _pending.isNotEmpty ||
          !world.commands.isEmpty);
    } finally {
      world.endFlush();
    }
    _advanceParkedReaders();
    _reportAgedParked();
  }

  void _applyPending() {
    if (_pending.isEmpty) return;
    for (var i = 0; i < _pending.length; i++) {
      final pending = _pending[i];
      final entity = pending.entity;
      if (!world.isAlive(entity)) continue;
      final owner = pending.ownedBy;
      if (owner != null) world.insertNow<OwnedBy>(entity, OwnedBy(owner));
      for (final part in pending.parts) {
        final type = part.runtimeType;
        if (world.stores.isRegistered(type)) {
          world.insertNowByType(type, entity, part);
        } else if (part is Tag) {
          throw StateError(
            'spawn(...) included tag $type, but no tag store is registered '
            'for it. Tag stores cannot be created from an instance; call '
            'registerTag<$type>() at install time.',
          );
        } else {
          (_parked[entity] ??= <Object>[]).add(part);
          _parkedAtFrame[entity] ??=
              world.resources.tryGet<FrameTime>()?.frame ?? 0;
        }
      }
    }
    _pending.clear();
  }

  bool _sweepOwnedOnce() {
    if (_owned.length == 0) return false;
    List<Entity>? doomed;
    for (var dense = 0; dense < _owned.length; dense++) {
      if (!world.isAlive(_owned.valueAt(dense).owner)) {
        (doomed ??= <Entity>[]).add(
          world.entities.resolve(_owned.entityIndexAt(dense)),
        );
      }
    }
    if (doomed == null) return false;
    for (final entity in doomed) {
      if (world.isAlive(entity)) world.despawnNow(entity);
    }
    return true;
  }

  /// Reports parts that still have no store.
  void _reportAgedParked() {
    if (_parked.isEmpty) return;
    final sink = onDiagnostic;
    if (sink == null) return;
    final frame = world.resources.tryGet<FrameTime>()?.frame ?? 0;
    List<Entity>? dead;
    for (final entry in _parked.entries) {
      if (!world.isAlive(entry.key)) {
        (dead ??= <Entity>[]).add(entry.key);
        continue;
      }
      final parkedAt = _parkedAtFrame[entry.key];
      if (parkedAt == null || frame - parkedAt < 2) continue;
      for (final part in entry.value) {
        final type = part.runtimeType;
        if (!_reportedParkedTypes.add(type)) continue;
        sink(
          'A spawn(...) part of type $type is still parked: no typed use '
          '(a query naming $type, registerComponent<$type>()) has '
          'registered its store, so it is invisible to queries. Register '
          'it at install time if that is not the intent. (Reported once '
          'per type.)',
        );
      }
    }
    if (dead != null) {
      for (final entity in dead) {
        _parked.remove(entity);
        _parkedAtFrame.remove(entity);
      }
    }
  }

  // Reuses event readers owned by widgets.

  final Map<Type, List<EventReader<Object>>> _parkedReaders =
      <Type, List<EventReader<Object>>>{};

  /// Leases a reader for [E] (registering the channel on first use),
  /// positioned at the channel end. Return it with [releaseReader].
  EventReader<E> acquireReader<E extends Object>() {
    world.registerEvent<E>();
    final parked = _parkedReaders[E];
    if (parked != null && parked.isNotEmpty) {
      final recycled = parked.removeLast() as EventReader<E>;
      recycled.consume();
      return recycled;
    }
    return world.eventChannel<E>().reader();
  }

  /// Returns a leased [reader] to the pool; see [acquireReader].
  void releaseReader<E extends Object>(EventReader<E> reader) {
    reader.consume();
    (_parkedReaders[E] ??= <EventReader<Object>>[]).add(reader);
  }

  void _advanceParkedReaders() {
    if (_parkedReaders.isEmpty) return;
    for (final readers in _parkedReaders.values) {
      for (var i = 0; i < readers.length; i++) {
        readers[i].consume();
      }
    }
  }

  /// Drops all pending spawns.
  void reset() {
    _pending.clear();
    _parked.clear();
    _parkedAtFrame.clear();
  }
}

final class _PendingSpawn {
  final Entity entity;
  final List<Object> parts;
  final Entity? ownedBy;

  _PendingSpawn(this.entity, this.parts, this.ownedBy);
}
