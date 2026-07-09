import 'package:meta/meta.dart';

import 'component_store.dart';

/// Dense object storage for `@ObjectComponent` types.
///
/// Holds Dart references in a [List] kept parallel to the dense entity rows of
/// the base sparse set. Values are the authoritative data and are handed
/// directly to query callbacks.
final class ObjectComponentStore<T> extends ComponentStore {
  List<T?> _values;

  ObjectComponentStore({super.denseCapacity = 8, super.sparseCapacity = 16})
    : _values = List<T?>.filled(denseCapacity, null, growable: false);

  /// Inserts or replaces the component [value] for [entityIndex].
  void insert(int entityIndex, T value) {
    final dense = putSlot(entityIndex);
    _values[dense] = value;
    bumpRevision();
  }

  @override
  void insertDynamic(int entityIndex, Object? value) =>
      insert(entityIndex, value as T);

  /// The value stored at dense row [dense].
  T valueAt(int dense) => _values[dense] as T;

  /// The value for [entityIndex], or `null` if it has no such component.
  T? valueOf(int entityIndex) {
    final dense = denseIndexOf(entityIndex);
    return dense < 0 ? null : _values[dense];
  }

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
