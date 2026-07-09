import 'dart:typed_data';

import 'entity.dart';

/// Allocator and validator for generational [Entity] handles.
///
/// Backed by packed typed arrays:
///
/// * [_generations] — the current generation of each slot.
/// * [_alive] — `1` if the slot currently holds a live entity, else `0`.
/// * [_freeIndices] — a stack of slot indices available for reuse.
///
/// Indices are reused in LIFO order; each reuse bumps the slot generation so
/// previously issued handles to that slot stop validating.
final class EntityRegistry {
  Uint32List _generations;
  Uint8List _alive;
  Uint32List _freeIndices;

  /// Number of slots in the free stack.
  int _freeCount = 0;

  /// Highest slot index ever allocated, plus one (the live capacity in use).
  int _count = 0;

  EntityRegistry({int initialCapacity = 64})
      : _generations = Uint32List(initialCapacity),
        _alive = Uint8List(initialCapacity),
        _freeIndices = Uint32List(initialCapacity);

  /// Number of slots currently occupied by live entities.
  int get aliveCount => _count - _freeCount;

  /// Allocates a new live entity, reusing a freed slot when available.
  Entity spawn() {
    final int index;
    if (_freeCount > 0) {
      index = _freeIndices[--_freeCount];
    } else {
      index = _count;
      _ensureCapacity(index + 1);
      _count = index + 1;
    }
    _alive[index] = 1;
    return Entity(index, _generations[index]);
  }

  /// Returns whether [entity] refers to a currently live slot of the matching
  /// generation. Stale handles (despawned, then possibly reused) return false.
  bool isAlive(Entity entity) {
    final index = entity.index;
    if (index >= _count) return false;
    return _alive[index] == 1 && _generations[index] == entity.generation;
  }

  /// Despawns [entity], freeing its slot for reuse and bumping the generation.
  ///
  /// Returns `true` if the entity was live and is now despawned, `false` if the
  /// handle was already stale.
  bool despawn(Entity entity) {
    if (!isAlive(entity)) return false;
    final index = entity.index;
    _alive[index] = 0;
    // Wrap-around is intentional and harmless for handle disambiguation.
    _generations[index] = (_generations[index] + 1) & 0xFFFFFFFF;
    _pushFree(index);
    return true;
  }

  /// Despawns every live entity at once — the entity side of `World.reset`.
  ///
  /// Bumps the generation of every live slot, so all previously issued
  /// handles stop validating exactly as if each entity had been [despawn]ed
  /// individually, and rebuilds the free stack wholesale (dead slots are
  /// already stale and keep their generation). Slots are stacked so reuse
  /// after the reset starts from index 0 upward.
  void despawnAll() {
    if (_freeIndices.length < _count) {
      _freeIndices = _grow32(_freeIndices, _count);
    }
    for (var i = 0; i < _count; i++) {
      if (_alive[i] == 1) {
        _alive[i] = 0;
        // Wrap-around is intentional and harmless, as in despawn.
        _generations[i] = (_generations[i] + 1) & 0xFFFFFFFF;
      }
      // Rebuilding replaces any previous stack contents, so every slot
      // appears exactly once; the last pushed (slot 0) pops first.
      _freeIndices[_count - 1 - i] = i;
    }
    _freeCount = _count;
  }

  /// Resolves a slot [index] to a live [Entity] handle at the current
  /// generation. Used by queries that iterate dense entity-index rows.
  Entity resolve(int index) => Entity(index, _generations[index]);

  void _pushFree(int index) {
    if (_freeCount >= _freeIndices.length) {
      _freeIndices = _grow32(_freeIndices, _freeCount + 1);
    }
    _freeIndices[_freeCount++] = index;
  }

  void _ensureCapacity(int needed) {
    if (needed <= _generations.length) return;
    var newCap = _generations.isEmpty ? 64 : _generations.length;
    while (newCap < needed) {
      newCap *= 2;
    }
    _generations = _grow32(_generations, newCap, exact: true);
    final newAlive = Uint8List(newCap)..setRange(0, _count, _alive);
    _alive = newAlive;
  }

  static Uint32List _grow32(Uint32List source, int needed,
      {bool exact = false}) {
    var newCap = exact ? needed : (source.isEmpty ? 64 : source.length);
    if (!exact) {
      while (newCap < needed) {
        newCap *= 2;
      }
    }
    return Uint32List(newCap)..setRange(0, source.length, source);
  }
}
