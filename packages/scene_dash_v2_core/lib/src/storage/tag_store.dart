import 'package:meta/meta.dart';

import 'component_store.dart';

/// Storage for `@Tag` types: entity membership with no payload.
///
/// A tag store only tracks which entities carry the tag, so it adds nothing to
/// the base sparse set beyond a payload-free insert API.
///
/// Observers still receive an instance: tags are data-free, so every instance
/// stands for the tag equally, and the store keeps the first instance that
/// passed through [insertDynamic] (spawn lists and `world.add` always carry
/// one) as the canonical witness handed to `onAdd`/`onRemove` callbacks.
final class TagStore extends ComponentStore {
  Object? _witness;

  TagStore({super.denseCapacity = 8, super.sparseCapacity = 16});

  /// Adds the tag to [entityIndex] (idempotent).
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
