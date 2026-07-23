import 'dart:typed_data';

import 'package:meta/meta.dart';

abstract base class ComponentStore {
  Uint32List _denseEntities;
  Uint32List _sparse;
  int _length = 0;
  int _revision = 0;

  void Function(int entityIndex, Object? payload)? onAdded;

  void Function(int entityIndex, Object? payload)? onRemoved;

  ComponentStore({int denseCapacity = 8, int sparseCapacity = 16})
    : _denseEntities = Uint32List(denseCapacity),
      _sparse = Uint32List(sparseCapacity);

  int get length => _length;

  int get revision => _revision;

  bool containsIndex(int entityIndex) => denseIndexOf(entityIndex) >= 0;

  int denseIndexOf(int entityIndex) {
    if (entityIndex >= _sparse.length) return -1;
    final stamped = _sparse[entityIndex];
    if (stamped == 0) return -1;
    final dense = stamped - 1;
    if (dense >= _length || _denseEntities[dense] != entityIndex) return -1;
    return dense;
  }

  int entityIndexAt(int dense) => _denseEntities[dense];

  void insertDynamic(int entityIndex, Object? value);

  void removeEntityIndex(int entityIndex) {
    final removed = onRemoved;
    if (removed == null) {
      removeSlot(entityIndex);
      return;
    }
    final dense = denseIndexOf(entityIndex);
    if (dense < 0) return;
    final payload = payloadAt(dense);
    removeSlot(entityIndex);
    removed(entityIndex, payload);
  }

  void clear() {
    if (_length == 0) return;
    for (var dense = 0; dense < _length; dense++) {
      _sparse[_denseEntities[dense]] = 0;
      clearPayload(dense);
    }
    _length = 0;
    bumpRevision();
  }

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

  @protected
  void bumpRevision() {
    _revision += 1;
  }

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

  @protected
  Object? payloadAt(int dense) => null;

  @protected
  void movePayload(int from, int to) {}

  @protected
  void clearPayload(int dense) {}

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
