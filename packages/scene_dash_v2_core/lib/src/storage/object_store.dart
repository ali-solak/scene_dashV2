import 'package:meta/meta.dart';

import 'component_store.dart';

final class ObjectComponentStore<T> extends ComponentStore {
  List<T?> _values;

  ObjectComponentStore({super.denseCapacity = 8, super.sparseCapacity = 16})
    : _values = List<T?>.filled(denseCapacity, null, growable: false);

  void insert(int entityIndex, T value) {
    final existing = denseIndexOf(entityIndex);
    if (existing >= 0) {
      _values[existing] = value;
      bumpRevision();
      return;
    }
    final dense = putSlot(entityIndex);
    _values[dense] = value;
    bumpRevision();
    onAdded?.call(entityIndex, value);
  }

  @override
  void insertDynamic(int entityIndex, Object? value) =>
      insert(entityIndex, value as T);

  T valueAt(int dense) => _values[dense] as T;

  T? valueOf(int entityIndex) {
    final dense = denseIndexOf(entityIndex);
    return dense < 0 ? null : _values[dense];
  }

  @override
  @protected
  Object? payloadAt(int dense) => _values[dense];

  @override
  @protected
  void movePayload(int from, int to) {
    _values[to] = _values[from];
  }

  @override
  @protected
  void clearPayload(int dense) {
    _values[dense] = null;
  }

  @override
  @protected
  void growPayload(int newCapacity) {
    final grown = List<T?>.filled(newCapacity, null, growable: false);
    for (var i = 0; i < length; i++) {
      grown[i] = _values[i];
    }
    _values = grown;
  }
}
