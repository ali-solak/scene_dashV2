import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Base sparse-set storage shared by every component store.
///
/// The sparse set keeps three logical pieces of state:
///
/// * a packed *dense* array of entity indices that currently have this
///   component ([_denseEntities], `0..length`);
/// * a *sparse* array indexed by entity index, holding `denseIndex + 1`
///   (so `0` is the "absent" sentinel);
/// * payload rows owned by subclasses, kept parallel to the dense array.
///
/// Removal is O(1) swap-removal: the last dense row is moved into the hole.
/// Subclasses keep their payload consistent by overriding the [movePayload],
/// [clearPayload] and [growPayload] hooks.
///
/// All stores use `denseIndex + 1` in the sparse array and treat `0` as the
/// missing sentinel, and all use geometric capacity growth.
abstract base class ComponentStore {
  Uint32List _denseEntities;
  Uint32List _sparse;
  int _length = 0;
  int _revision = 0;

  ComponentStore({int denseCapacity = 8, int sparseCapacity = 16})
    : _denseEntities = Uint32List(denseCapacity),
      _sparse = Uint32List(sparseCapacity);

  /// Number of entities currently stored.
  int get length => _length;

  /// Structural/content revision for this store.
  ///
  /// Incremented when a component is inserted, replaced, or removed. Query and
  /// integration code can cache this to skip work when the store has not
  /// changed since its last pass.
  int get revision => _revision;

  /// Whether [entityIndex] currently has this component.
  bool containsIndex(int entityIndex) => denseIndexOf(entityIndex) >= 0;

  /// The dense row of [entityIndex], or `-1` if it is not stored.
  int denseIndexOf(int entityIndex) {
    if (entityIndex >= _sparse.length) return -1;
    final stamped = _sparse[entityIndex];
    if (stamped == 0) return -1;
    final dense = stamped - 1;
    if (dense >= _length || _denseEntities[dense] != entityIndex) return -1;
    return dense;
  }

  /// The entity index stored at dense row [dense].
  int entityIndexAt(int dense) => _denseEntities[dense];

  /// Inserts [value] for [entityIndex], replacing any existing component.
  ///
  /// Implemented by typed subclasses; [value] is ignored by tag stores.
  void insertDynamic(int entityIndex, Object? value);

  /// Removes the component of [entityIndex] if present (swap removal).
  void removeEntityIndex(int entityIndex) => removeSlot(entityIndex);

  /// Removes every entity from this store at once — the store side of
  /// `World.reset`. The store stays registered and keeps its capacity.
  ///
  /// Clears each payload row (releasing the object references) and bumps the
  /// revision, so revision-cached consumers (like the scene mount adapter)
  /// see the emptied membership on their next pass. A store that is already
  /// empty is left untouched, revision included.
  void clear() {
    if (_length == 0) return;
    for (var dense = 0; dense < _length; dense++) {
      _sparse[_denseEntities[dense]] = 0;
      clearPayload(dense);
    }
    _length = 0;
    bumpRevision();
  }

  /// Allocates (or returns the existing) dense row for [entityIndex].
  ///
  /// The caller is responsible for writing the payload at the returned row.
  @protected
  int putSlot(int entityIndex) {
    final existing = denseIndexOf(entityIndex);
    if (existing >= 0) return existing;
    _ensureSparse(entityIndex);
    final dense = _length;
    _ensureDense(dense + 1);
    _denseEntities[dense] = entityIndex;
    _sparse[entityIndex] = dense + 1;
    _length = dense + 1;
    return dense;
  }

  /// Marks this store as changed.
  @protected
  void bumpRevision() {
    _revision += 1;
  }

  /// Removes [entityIndex] via swap removal. Returns the freed dense row, or
  /// `-1` if the entity was not stored.
  @protected
  int removeSlot(int entityIndex) {
    final dense = denseIndexOf(entityIndex);
    if (dense < 0) return -1;
    final last = _length - 1;
    if (dense != last) {
      final movedEntity = _denseEntities[last];
      _denseEntities[dense] = movedEntity;
      _sparse[movedEntity] = dense + 1;
      movePayload(last, dense);
    }
    _sparse[entityIndex] = 0;
    _length = last;
    clearPayload(last);
    bumpRevision();
    return dense;
  }

  /// Hook: move payload from dense row [from] to row [to] during swap removal.
  @protected
  void movePayload(int from, int to) {}

  /// Hook: clear the payload at the now-unused dense row [dense].
  @protected
  void clearPayload(int dense) {}

  /// Hook: grow payload rows to at least [newCapacity] dense slots.
  @protected
  void growPayload(int newCapacity) {}

  void _ensureSparse(int entityIndex) {
    if (entityIndex < _sparse.length) return;
    var newCap = _sparse.isEmpty ? 16 : _sparse.length;
    while (newCap <= entityIndex) {
      newCap *= 2;
    }
    _sparse = Uint32List(newCap)..setRange(0, _sparse.length, _sparse);
  }

  void _ensureDense(int needed) {
    if (needed <= _denseEntities.length) return;
    var newCap = _denseEntities.isEmpty ? 8 : _denseEntities.length;
    while (newCap < needed) {
      newCap *= 2;
    }
    _denseEntities = Uint32List(newCap)..setRange(0, _length, _denseEntities);
    growPayload(newCap);
  }
}
