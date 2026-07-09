import 'component_store.dart';

/// Storage for `@Tag` types: entity membership with no payload.
///
/// A tag store only tracks which entities carry the tag, so it adds nothing to
/// the base sparse set beyond a payload-free insert API.
final class TagStore extends ComponentStore {
  TagStore({super.denseCapacity = 8, super.sparseCapacity = 16});

  /// Adds the tag to [entityIndex] (idempotent).
  void add(int entityIndex) {
    if (containsIndex(entityIndex)) return;
    putSlot(entityIndex);
    bumpRevision();
  }

  @override
  void insertDynamic(int entityIndex, Object? value) => add(entityIndex);
}
