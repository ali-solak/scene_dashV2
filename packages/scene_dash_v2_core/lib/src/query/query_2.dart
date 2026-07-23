import '../entity/entity.dart';
import '../storage/component_store.dart';
import '../storage/object_store.dart';
import '../world/world.dart';
import 'query.dart';

typedef Query2Callback<A, B> = void Function(Entity entity, A a, B b);

typedef Query2UntilCallback<A, B> = bool Function(Entity entity, A a, B b);

final class Query2<A, B> extends Query {
  @override
  String get debugLabel => 'query2<$A, $B>';

  @override
  int get debugRowEstimate => Query.chooseDriver(_driverCandidates).length;

  final World _world;
  final ObjectComponentStore<A> _a;
  final ObjectComponentStore<B> _b;
  final List<ComponentStore> _withStores;
  final List<ComponentStore> _withoutStores;

  late final List<ComponentStore> _driverCandidates = <ComponentStore>[
    _a,
    _b,
    ..._withStores,
  ];

  Query2(this._world, this._a, this._b, this._withStores, this._withoutStores);

  void each(Query2Callback<A, B> callback) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);

        final aDense = driverIsA ? i : _a.denseIndexOf(entityIndex);
        if (aDense < 0) continue;

        final bDense = driverIsB ? i : _b.denseIndexOf(entityIndex);
        if (bDense < 0) continue;

        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }

        callback(
          _world.entities.resolve(entityIndex),
          _a.valueAt(aDense),
          _b.valueAt(bDense),
        );
      }
    } finally {
      _world.endQuery();
    }
  }

  void eachUntil(Query2UntilCallback<A, B> callback) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);

        final aDense = driverIsA ? i : _a.denseIndexOf(entityIndex);
        if (aDense < 0) continue;

        final bDense = driverIsB ? i : _b.denseIndexOf(entityIndex);
        if (bDense < 0) continue;

        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }

        if (!callback(
          _world.entities.resolve(entityIndex),
          _a.valueAt(aDense),
          _b.valueAt(bDense),
        )) {
          return;
        }
      }
    } finally {
      _world.endQuery();
    }
  }

  (Entity, A, B)? firstWhere(Query2UntilCallback<A, B> predicate) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        final aDense = driverIsA ? i : _a.denseIndexOf(entityIndex);
        if (aDense < 0) continue;
        final bDense = driverIsB ? i : _b.denseIndexOf(entityIndex);
        if (bDense < 0) continue;
        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }
        final entity = _world.entities.resolve(entityIndex);
        final a = _a.valueAt(aDense);
        final b = _b.valueAt(bDense);
        if (predicate(entity, a, b)) return (entity, a, b);
      }
      return null;
    } finally {
      _world.endQuery();
    }
  }

  bool any(Query2UntilCallback<A, B> predicate) {
    var found = false;
    eachUntil((entity, a, b) {
      if (predicate(entity, a, b)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  bool get(Entity entity, Query2Callback<A, B> found) {
    if (!_world.isAlive(entity)) return false;
    final entityIndex = entity.index;
    final aDense = _a.denseIndexOf(entityIndex);
    if (aDense < 0) return false;
    final bDense = _b.denseIndexOf(entityIndex);
    if (bDense < 0) return false;
    if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
      return false;
    }
    found(entity, _a.valueAt(aDense), _b.valueAt(bDense));
    return true;
  }

  (A, B)? components(Entity entity) {
    if (!_world.isAlive(entity)) return null;
    final entityIndex = entity.index;
    final aDense = _a.denseIndexOf(entityIndex);
    if (aDense < 0) return null;
    final bDense = _b.denseIndexOf(entityIndex);
    if (bDense < 0) return null;
    if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
      return null;
    }
    return (_a.valueAt(aDense), _b.valueAt(bDense));
  }

  bool get isEmpty {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        if ((driverIsA ? i : _a.denseIndexOf(entityIndex)) < 0) continue;
        if ((driverIsB ? i : _b.denseIndexOf(entityIndex)) < 0) continue;
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

  int count() {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    var matches = 0;
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        if ((driverIsA ? i : _a.denseIndexOf(entityIndex)) < 0) continue;
        if ((driverIsB ? i : _b.denseIndexOf(entityIndex)) < 0) continue;
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

  (Entity, A, B)? singleOrNull() {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    _world.beginQuery(this);
    try {
      (Entity, A, B)? match;
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        final aDense = driverIsA ? i : _a.denseIndexOf(entityIndex);
        if (aDense < 0) continue;
        final bDense = driverIsB ? i : _b.denseIndexOf(entityIndex);
        if (bDense < 0) continue;
        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }
        if (match != null) {
          throw StateError(
            'Query2<$A, $B>.single: expected exactly one matching entity, '
            'found more than one.',
          );
        }
        match = (
          _world.entities.resolve(entityIndex),
          _a.valueAt(aDense),
          _b.valueAt(bDense),
        );
      }
      return match;
    } finally {
      _world.endQuery();
    }
  }

  (Entity, A, B) single() {
    final match = singleOrNull();
    if (match == null) {
      throw StateError(
        'Query2<$A, $B>.single: expected exactly one matching entity, found '
        'none.',
      );
    }
    return match;
  }
}
