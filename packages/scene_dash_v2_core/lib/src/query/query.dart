import '../storage/component_store.dart';

/// Shared helpers for the generated/runtime query types.
///
/// A query caches direct references to its component and filter stores and an
/// iteration plan, but never a permanent list of matching entities — membership
/// is re-checked every time the query runs, so it stays correct as entities
/// change.
abstract base class Query {
  /// Returns the store with the fewest entities among [candidates]; this is
  /// chosen as the iteration driver so the loop visits as few rows as possible.
  static ComponentStore chooseDriver(List<ComponentStore> candidates) {
    var driver = candidates[0];
    for (var i = 1; i < candidates.length; i++) {
      if (candidates[i].length < driver.length) {
        driver = candidates[i];
      }
    }
    return driver;
  }

  /// Whether [entityIndex] satisfies all `with` and `without` filters.
  static bool passesFilters(
    int entityIndex,
    List<ComponentStore> withStores,
    List<ComponentStore> withoutStores,
  ) {
    for (var i = 0; i < withStores.length; i++) {
      if (!withStores[i].containsIndex(entityIndex)) return false;
    }
    for (var i = 0; i < withoutStores.length; i++) {
      if (withoutStores[i].containsIndex(entityIndex)) return false;
    }
    return true;
  }
}
