import '../storage/component_store.dart';

abstract base class Query {
  String get debugLabel;

  int get debugRowEstimate;

  static ComponentStore chooseDriver(List<ComponentStore> candidates) {
    var driver = candidates[0];
    for (var i = 1; i < candidates.length; i++) {
      if (candidates[i].length < driver.length) {
        driver = candidates[i];
      }
    }
    return driver;
  }

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
