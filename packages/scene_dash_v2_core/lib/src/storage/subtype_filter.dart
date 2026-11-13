import 'component_store.dart';

final class SubtypeFilter<T> extends ComponentStore {
  SubtypeFilter(this._inner) : super(denseCapacity: 0, sparseCapacity: 0);

  final ComponentStore _inner;

  @override
  int get length => _inner.length;

  @override
  int get revision => _inner.revision;

  @override
  int entityIndexAt(int dense) => _inner.entityIndexAt(dense);

  @override
  Object? payloadOf(int entityIndex) {
    final value = _inner.payloadOf(entityIndex);
    return value is T ? value : null;
  }

  @override
  bool containsIndex(int entityIndex) => _inner.payloadOf(entityIndex) is T;

  @override
  int denseIndexOf(int entityIndex) =>
      containsIndex(entityIndex) ? _inner.denseIndexOf(entityIndex) : -1;

  @override
  void insertDynamic(int entityIndex, Object? value) =>
      throw UnsupportedError('SubtypeFilter<$T> is read-only.');
}
