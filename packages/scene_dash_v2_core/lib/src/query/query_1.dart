import '../entity/entity.dart';
import '../storage/component_store.dart';
import '../storage/object_store.dart';
import '../world/world.dart';
import 'query.dart';

typedef Query1Callback<A> = void Function(Entity entity, A a);

typedef Query1UntilCallback<A> = bool Function(Entity entity, A a);

final class Query1<A> extends Query {
  @override
  String get debugLabel => 'query<$A>';

  @override
  int get debugRowEstimate => Query.chooseDriver(_driverCandidates).length;

  final World _world;
  final ObjectComponentStore<A> _a;
  final List<ComponentStore> _withStores;
  final List<ComponentStore> _withoutStores;

  late final List<ComponentStore> _driverCandidates = <ComponentStore>[
    _a,
    ..._withStores,
  ];

  Query1(this._world, this._a, this._withStores, this._withoutStores);

  void each(Query1Callback<A> callback) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);

        final aDense = driverIsA ? i : _a.denseIndexOf(entityIndex);
        if (aDense < 0) continue;

        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }

        callback(_world.entities.resolve(entityIndex), _a.valueAt(aDense));
      }
    } finally {
      _world.endQuery();
    }
  }

  void eachUntil(Query1UntilCallback<A> callback) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);

        final aDense = driverIsA ? i : _a.denseIndexOf(entityIndex);
        if (aDense < 0) continue;

        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }

        if (!callback(
          _world.entities.resolve(entityIndex),
          _a.valueAt(aDense),
        )) {
          return;
        }
      }
    } finally {
      _world.endQuery();
    }
  }

  (Entity, A)? firstWhere(Query1UntilCallback<A> predicate) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        final aDense = driverIsA ? i : _a.denseIndexOf(entityIndex);
        if (aDense < 0) continue;
        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }
        final entity = _world.entities.resolve(entityIndex);
        final a = _a.valueAt(aDense);
        if (predicate(entity, a)) return (entity, a);
      }
      return null;
    } finally {
      _world.endQuery();
    }
  }

  bool any(Query1UntilCallback<A> predicate) {
    var found = false;
    eachUntil((entity, a) {
      if (predicate(entity, a)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  A? get(Entity entity) {
    if (!_world.isAlive(entity)) return null;
    final entityIndex = entity.index;
    final aDense = _a.denseIndexOf(entityIndex);
    if (aDense < 0) return null;
    if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
      return null;
    }
    return _a.valueAt(aDense);
  }

  (A,)? components(Entity entity) {
    final a = get(entity);
    return a == null ? null : (a,);
  }

  bool get isEmpty {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        if ((driverIsA ? i : _a.denseIndexOf(entityIndex)) < 0) continue;
        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }
        return false;
      }
      return true;
    } finally {
      _world.endQuery();
    }
  }

  (Entity, A)? singleOrNull() {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    _world.beginQuery(this);
    try {
      (Entity, A)? match;
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        final aDense = driverIsA ? i : _a.denseIndexOf(entityIndex);
        if (aDense < 0) continue;
        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }
        if (match != null) {
          throw StateError(
            'Query1<$A>.single: expected exactly one matching entity, found '
            'more than one.',
          );
        }
        match = (_world.entities.resolve(entityIndex), _a.valueAt(aDense));
      }
      return match;
    } finally {
      _world.endQuery();
    }
  }

  (Entity, A) single() {
    final match = singleOrNull();
    if (match == null) {
      throw StateError(
        'Query1<$A>.single: expected exactly one matching entity, found none.',
      );
    }
    return match;
  }

  int count() {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    var matches = 0;
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        if ((driverIsA ? i : _a.denseIndexOf(entityIndex)) < 0) continue;
        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }
        matches++;
      }
      return matches;
    } finally {
      _world.endQuery();
    }
  }

  int get driverLength => Query.chooseDriver(_driverCandidates).length;
}
