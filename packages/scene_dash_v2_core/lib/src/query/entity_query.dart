import '../entity/entity.dart';
import '../storage/component_store.dart';
import '../world/world.dart';
import 'query.dart';

typedef EntityQueryCallback = void Function(Entity entity);

typedef EntityQueryUntilCallback = bool Function(Entity entity);

final class EntityQuery extends Query {
  @override
  String get debugLabel => 'queryEntities';

  @override
  int get debugRowEstimate => Query.chooseDriver(_withStores).length;

  final World _world;
  final List<ComponentStore> _withStores;
  final List<ComponentStore> _withoutStores;

  EntityQuery(this._world, this._withStores, this._withoutStores)
    : assert(
        _withStores.isNotEmpty,
        'EntityQuery needs at least one required type to drive iteration.',
      );

  void each(EntityQueryCallback callback) {
    final driver = Query.chooseDriver(_withStores);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }
        callback(_world.entities.resolve(entityIndex));
      }
    } finally {
      _world.endQuery();
    }
  }

  void eachUntil(EntityQueryUntilCallback callback) {
    final driver = Query.chooseDriver(_withStores);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }
        if (!callback(_world.entities.resolve(entityIndex))) return;
      }
    } finally {
      _world.endQuery();
    }
  }

  Entity? firstWhere(EntityQueryUntilCallback predicate) {
    final driver = Query.chooseDriver(_withStores);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }
        final entity = _world.entities.resolve(entityIndex);
        if (predicate(entity)) return entity;
      }
      return null;
    } finally {
      _world.endQuery();
    }
  }

  Entity? get firstOrNull => firstWhere(_matchAll);

  static bool _matchAll(Entity entity) => true;

  bool any(EntityQueryUntilCallback predicate) {
    var found = false;
    eachUntil((entity) {
      if (predicate(entity)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  bool contains(Entity entity) {
    if (!_world.isAlive(entity)) return false;
    return Query.passesFilters(entity.index, _withStores, _withoutStores);
  }

  bool get isEmpty {
    final driver = Query.chooseDriver(_withStores);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        if (Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          return false;
        }
      }
      return true;
    } finally {
      _world.endQuery();
    }
  }

  int count() {
    final driver = Query.chooseDriver(_withStores);
    var matches = 0;
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        if (Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          matches++;
        }
      }
      return matches;
    } finally {
      _world.endQuery();
    }
  }
}
