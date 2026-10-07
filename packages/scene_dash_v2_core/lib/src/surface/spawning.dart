/// Deferred entity spawning.
library;

import '../diagnostics/name.dart';
import '../entity/entity.dart';
import '../events/event_channel.dart';
import '../state/despawn_after.dart';
import '../state/states.dart';
import '../storage/component_store.dart';
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

  // Cancels queued spawn/add callbacks on reset without a second command FIFO.
  int _resetEpoch = 0;
  final Map<Entity, List<Object>> _parked = <Entity, List<Object>>{};
  final Map<Entity, int> _parkedAtFrame = <Entity, int>{};
  final Set<Type> _reportedParkedTypes = <Type>{};
  int _parkedRevision = 0;
  int _reportedAtRevision = -1;
  int _lastDiagnosticFrame = -1;
  final ObjectComponentStore<OwnedBy> _owned;

  SpawnQueue._(this.world) : _owned = world.ensureObjectStore<OwnedBy>() {
    world
      ..ensureObjectStore<Name>()
      ..ensureObjectStore<DespawnAfter>()
      ..ensureObjectStore<DespawnOnExit>()
      ..stores.onCreated = _claimParked;
  }

  /// The world's queue, created on first use.
  static SpawnQueue of(World world) =>
      world.resources.getOrInsert<SpawnQueue>(() => SpawnQueue._(world));

  /// Reserves an entity now and queues [parts] for the next [flush].
  Entity enqueue(List<Object> parts, {Entity? ownedBy}) {
    final entity = world.entities.spawn();
    _queueParts(entity, parts, ownedBy);
    return entity;
  }

  /// Adds [part] to [entity] during the next [flush].
  void addPart(Entity entity, Object part) {
    _queueParts(entity, <Object>[part], null);
  }

  void _queueParts(Entity entity, List<Object> parts, Entity? ownedBy) {
    assert(parts.every(_checkPart));
    final epoch = _resetEpoch;
    world.commands.defer(entity, (world, entity) {
      if (epoch != _resetEpoch || !world.isAlive(entity)) return;
      _applyParts(entity, parts, ownedBy);
    });
  }

  /// Removes [T] at its position in the structural command FIFO, including
  /// parts that have not yet been claimed by a typed store.
  void removePart<T>(Entity entity) {
    world.commands.defer(entity, (world, entity) {
      final parts = _parked[entity];
      if (parts != null) {
        parts.removeWhere((part) => part is T);
        if (parts.isEmpty) {
          _parked.remove(entity);
          _parkedAtFrame.remove(entity);
        }
      }
      if (world.isAlive(entity)) world.removeNow<T>(entity);
    });
  }

  void _claimParked(Type type, ComponentStore store) {
    if (_parked.isEmpty) return;
    List<Entity>? emptied;
    for (final entry in _parked.entries) {
      final entity = entry.key;
      if (!world.isAlive(entity)) {
        (emptied ??= <Entity>[]).add(entity);
        continue;
      }
      entry.value.removeWhere((part) {
        if (!store.accepts(part)) return false;
        store.insertDynamic(entity.index, part);
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
        passes++;
        if (passes > 64) {
          throw StateError(
            'Spawns and owned despawns did not settle after 64 passes.',
          );
        }
      } while (_sweepOwnedOnce() ||
          (!world.commands.isEmpty && !world.commands.isApplying));
    } finally {
      world.endFlush();
    }
    _reportAgedParked();
  }

  void _applyParts(Entity entity, List<Object> parts, Entity? owner) {
    if (owner != null) world.insertNow<OwnedBy>(entity, OwnedBy(owner));
    for (final part in parts) {
      final type = part.runtimeType;
      if (world.stores.isRegistered(type)) {
        world.insertNowByType(type, entity, part);
      } else if (part is Tag) {
        world.stores.ensureTagByType(type);
        world.insertNowByType(type, entity, part);
      } else if (world.stores.supertypeStoreAccepting(part) case final store?) {
        store.insertDynamic(entity.index, part);
      } else {
        (_parked[entity] ??= <Object>[]).add(part);
        _parkedRevision++;
        _parkedAtFrame[entity] ??=
            world.resources.tryGet<FrameTime>()?.frame ?? 0;
      }
    }
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
    if (_parked.isEmpty || _reportedAtRevision == _parkedRevision) return;
    final sink = onDiagnostic;
    if (sink == null) return;
    final frame = world.resources.tryGet<FrameTime>()?.frame ?? 0;
    if (_lastDiagnosticFrame == frame) return;
    _lastDiagnosticFrame = frame;
    var waitingToAge = false;
    List<Entity>? dead;
    for (final entry in _parked.entries) {
      if (!world.isAlive(entry.key)) {
        (dead ??= <Entity>[]).add(entry.key);
        continue;
      }
      final parkedAt = _parkedAtFrame[entry.key];
      if (parkedAt == null || frame - parkedAt < 2) {
        waitingToAge = true;
        continue;
      }
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
    if (!waitingToAge) _reportedAtRevision = _parkedRevision;
  }

  /// Drops unclaimed components when an entity is despawned by the world.
  void discard(Entity entity) {
    _parked.remove(entity);
    _parkedAtFrame.remove(entity);
  }

  /// Leases a reader for [E] (registering the channel on first use),
  /// positioned at the channel end. Return it with [releaseReader].
  EventReader<E> acquireReader<E extends Object>() {
    world.registerEvent<E>();
    return world.eventChannel<E>().reader();
  }

  /// Disposes a leased [reader]; see [acquireReader]. Disposed readers no
  /// longer participate in channel maintenance or hold back event retention.
  void releaseReader<E extends Object>(EventReader<E> reader) {
    reader.dispose();
  }

  /// Drops all pending spawns.
  void reset() {
    _resetEpoch++;
    _parked.clear();
    _parkedAtFrame.clear();
    _parkedRevision++;
    _reportedAtRevision = -1;
    _lastDiagnosticFrame = -1;
  }
}

bool _checkPart(Object part) {
  if (part is Type || part is Future || part is Iterable || part is Function) {
    throw ArgumentError.value(
      part,
      'part',
      'spawn(...)/add(...) takes component instances. Got a '
          '${part.runtimeType}: pass Enemy() rather than Enemy or '
          'Enemy.new, await futures first, and spread nested lists with '
          '`...`.',
    );
  }
  return true;
}
