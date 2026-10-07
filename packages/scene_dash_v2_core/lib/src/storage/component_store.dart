import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'store_membership.dart';

abstract interface class StoreChangeListener {
  void rowChanged(int entityIndex);

  void cleared();
}

abstract base class ComponentStore {
  Uint32List _denseEntities;
  Uint32List _sparse;
  int _length = 0;
  int _revision = 0;

  void Function(int entityIndex, Object? payload)? onAdded;

  void Function(int entityIndex, Object? payload)? onRemoved;

  StoreChangeListener? _changeListener;

  StoreMembership? _membership;
  int _membershipId = 0;

  ComponentStore({int denseCapacity = 8, int sparseCapacity = 16})
    : _denseEntities = Uint32List(denseCapacity),
      _sparse = Uint32List(sparseCapacity);

  int get length => _length;

  void addChangeListener(StoreChangeListener listener) {
    final current = _changeListener;
    _changeListener = switch (current) {
      null => listener,
      _ChangeFanOut(:final listeners) => _ChangeFanOut([
        ...listeners,
        listener,
      ]),
      _ => _ChangeFanOut([current, listener]),
    };
  }

  void removeChangeListener(StoreChangeListener listener) {
    final current = _changeListener;
    if (identical(current, listener)) {
      _changeListener = null;
    } else if (current is _ChangeFanOut) {
      final rest = [
        for (final l in current.listeners)
          if (!identical(l, listener)) l,
      ];
      _changeListener = rest.length == 1 ? rest.single : _ChangeFanOut(rest);
    }
  }

  void attachMembership(StoreMembership membership, int id) {
    assert(_membership == null, 'A store can belong to one registry only.');
    _membership = membership;
    _membershipId = id;
    for (var dense = 0; dense < _length; dense++) {
      membership.add(_denseEntities[dense], id);
    }
  }

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

  bool accepts(Object? value) => false;

  bool holdsSubtype<U>() => false;

  Object? payloadOf(int entityIndex) {
    final dense = denseIndexOf(entityIndex);
    return dense < 0 ? null : payloadAt(dense);
  }

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
    final membership = _membership;
    for (var dense = 0; dense < _length; dense++) {
      final entityIndex = _denseEntities[dense];
      _sparse[entityIndex] = 0;
      membership?.remove(entityIndex, _membershipId);
      clearPayload(dense);
    }
    _length = 0;
    bumpRevision();
    _changeListener?.cleared();
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
    _membership?.add(entityIndex, _membershipId);
    return dense;
  }

  @protected
  void notifyRowChanged(int entityIndex) =>
      _changeListener?.rowChanged(entityIndex);

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
    _membership?.remove(entityIndex, _membershipId);
    _length = last;
    clearPayload(last);
    bumpRevision();
    _changeListener?.rowChanged(entityIndex);
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

final class _ChangeFanOut implements StoreChangeListener {
  _ChangeFanOut(this.listeners);

  final List<StoreChangeListener> listeners;

  @override
  void rowChanged(int entityIndex) {
    for (final listener in listeners) {
      listener.rowChanged(entityIndex);
    }
  }

  @override
  void cleared() {
    for (final listener in listeners) {
      listener.cleared();
    }
  }
}
