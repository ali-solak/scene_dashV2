import 'package:meta/meta.dart';

import 'component_store.dart';

final class TagStore extends ComponentStore {
  Object? _witness;

  TagStore({super.denseCapacity = 8, super.sparseCapacity = 16});

  void add(int entityIndex) {
    if (containsIndex(entityIndex)) return;
    putSlot(entityIndex);
    bumpRevision();
    onAdded?.call(entityIndex, _witness);
  }

  @override
  void insertDynamic(int entityIndex, Object? value) {
    _witness ??= value;
    add(entityIndex);
  }

  @override
  @protected
  Object? payloadAt(int dense) => _witness;
}
