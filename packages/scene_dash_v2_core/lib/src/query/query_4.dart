import '../entity/entity.dart';
import '../storage/component_store.dart';
import '../storage/object_store.dart';
import '../world/world.dart';
import 'query.dart';

typedef Query4Callback<A, B, C, D> =
    void Function(Entity entity, A a, B b, C c, D d);

typedef Query4UntilCallback<A, B, C, D> =
    bool Function(Entity entity, A a, B b, C c, D d);

final class Query4<A, B, C, D> extends Query {
  @override
  String get debugLabel => 'query4<$A, $B, $C, $D>';

  @override
  int get debugRowEstimate => Query.chooseDriver(_driverCandidates).length;

  final World _world;
  final ObjectComponentStore<A> _a;
  final ObjectComponentStore<B> _b;
  final ObjectComponentStore<C> _c;
  final ObjectComponentStore<D> _d;
  final List<ComponentStore> _withStores;
  final List<ComponentStore> _withoutStores;

  late final List<ComponentStore> _driverCandidates = <ComponentStore>[
    _a,
    _b,
    _c,
    _d,
    ..._withStores,
  ];

  Query4(
    this._world,
    this._a,
    this._b,
    this._c,
    this._d,
    this._withStores,
    this._withoutStores,
  );

  void each(Query4Callback<A, B, C, D> callback) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    final driverIsC = identical(driver, _c);
    final driverIsD = identical(driver, _d);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);

        final aDense = driverIsA ? i : _a.denseIndexOf(entityIndex);
        if (aDense < 0) continue;

        final bDense = driverIsB ? i : _b.denseIndexOf(entityIndex);
        if (bDense < 0) continue;

        final cDense = driverIsC ? i : _c.denseIndexOf(entityIndex);
        if (cDense < 0) continue;

        final dDense = driverIsD ? i : _d.denseIndexOf(entityIndex);
        if (dDense < 0) continue;

        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }

        callback(
          _world.entities.resolve(entityIndex),
          _a.valueAt(aDense),
          _b.valueAt(bDense),
          _c.valueAt(cDense),
          _d.valueAt(dDense),
        );
      }
    } finally {
      _world.endQuery();
    }
  }

  void eachUntil(Query4UntilCallback<A, B, C, D> callback) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    final driverIsC = identical(driver, _c);
    final driverIsD = identical(driver, _d);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);

        final aDense = driverIsA ? i : _a.denseIndexOf(entityIndex);
        if (aDense < 0) continue;

        final bDense = driverIsB ? i : _b.denseIndexOf(entityIndex);
        if (bDense < 0) continue;

        final cDense = driverIsC ? i : _c.denseIndexOf(entityIndex);
        if (cDense < 0) continue;

        final dDense = driverIsD ? i : _d.denseIndexOf(entityIndex);
        if (dDense < 0) continue;

        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }

        if (!callback(
          _world.entities.resolve(entityIndex),
          _a.valueAt(aDense),
          _b.valueAt(bDense),
          _c.valueAt(cDense),
          _d.valueAt(dDense),
        )) {
          return;
        }
      }
    } finally {
      _world.endQuery();
    }
  }

  (Entity, A, B, C, D)? firstWhere(Query4UntilCallback<A, B, C, D> predicate) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    final driverIsC = identical(driver, _c);
    final driverIsD = identical(driver, _d);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        final aDense = driverIsA ? i : _a.denseIndexOf(entityIndex);
        if (aDense < 0) continue;
        final bDense = driverIsB ? i : _b.denseIndexOf(entityIndex);
        if (bDense < 0) continue;
        final cDense = driverIsC ? i : _c.denseIndexOf(entityIndex);
        if (cDense < 0) continue;
        final dDense = driverIsD ? i : _d.denseIndexOf(entityIndex);
        if (dDense < 0) continue;
        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }
        final entity = _world.entities.resolve(entityIndex);
        final a = _a.valueAt(aDense);
        final b = _b.valueAt(bDense);
        final c = _c.valueAt(cDense);
        final d = _d.valueAt(dDense);
        if (predicate(entity, a, b, c, d)) return (entity, a, b, c, d);
      }
      return null;
    } finally {
      _world.endQuery();
    }
  }

  bool any(Query4UntilCallback<A, B, C, D> predicate) {
    var found = false;
    eachUntil((entity, a, b, c, d) {
      if (predicate(entity, a, b, c, d)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  bool get(Entity entity, Query4Callback<A, B, C, D> found) {
    if (!_world.isAlive(entity)) return false;
    final entityIndex = entity.index;
    final aDense = _a.denseIndexOf(entityIndex);
    if (aDense < 0) return false;
    final bDense = _b.denseIndexOf(entityIndex);
    if (bDense < 0) return false;
    final cDense = _c.denseIndexOf(entityIndex);
    if (cDense < 0) return false;
    final dDense = _d.denseIndexOf(entityIndex);
    if (dDense < 0) return false;
    if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
      return false;
    }
    found(
      entity,
      _a.valueAt(aDense),
      _b.valueAt(bDense),
      _c.valueAt(cDense),
      _d.valueAt(dDense),
    );
    return true;
  }

  (A, B, C, D)? components(Entity entity) {
    if (!_world.isAlive(entity)) return null;
    final entityIndex = entity.index;
    final aDense = _a.denseIndexOf(entityIndex);
    if (aDense < 0) return null;
    final bDense = _b.denseIndexOf(entityIndex);
    if (bDense < 0) return null;
    final cDense = _c.denseIndexOf(entityIndex);
    if (cDense < 0) return null;
    final dDense = _d.denseIndexOf(entityIndex);
    if (dDense < 0) return null;
    if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
      return null;
    }
    return (
      _a.valueAt(aDense),
      _b.valueAt(bDense),
      _c.valueAt(cDense),
      _d.valueAt(dDense),
    );
  }

  bool get isEmpty {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    final driverIsC = identical(driver, _c);
    final driverIsD = identical(driver, _d);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        if ((driverIsA ? i : _a.denseIndexOf(entityIndex)) < 0) continue;
        if ((driverIsB ? i : _b.denseIndexOf(entityIndex)) < 0) continue;
        if ((driverIsC ? i : _c.denseIndexOf(entityIndex)) < 0) continue;
        if ((driverIsD ? i : _d.denseIndexOf(entityIndex)) < 0) continue;
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
    final driverIsC = identical(driver, _c);
    final driverIsD = identical(driver, _d);
    var matches = 0;
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        if ((driverIsA ? i : _a.denseIndexOf(entityIndex)) < 0) continue;
        if ((driverIsB ? i : _b.denseIndexOf(entityIndex)) < 0) continue;
        if ((driverIsC ? i : _c.denseIndexOf(entityIndex)) < 0) continue;
        if ((driverIsD ? i : _d.denseIndexOf(entityIndex)) < 0) continue;
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

  (Entity, A, B, C, D)? singleOrNull() {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    final driverIsC = identical(driver, _c);
    final driverIsD = identical(driver, _d);
    _world.beginQuery(this);
    try {
      (Entity, A, B, C, D)? match;
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        final aDense = driverIsA ? i : _a.denseIndexOf(entityIndex);
        if (aDense < 0) continue;
        final bDense = driverIsB ? i : _b.denseIndexOf(entityIndex);
        if (bDense < 0) continue;
        final cDense = driverIsC ? i : _c.denseIndexOf(entityIndex);
        if (cDense < 0) continue;
        final dDense = driverIsD ? i : _d.denseIndexOf(entityIndex);
        if (dDense < 0) continue;
        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }
        if (match != null) {
          throw StateError(
            'Query4<$A, $B, $C, $D>.single: expected exactly one matching '
            'entity, found more than one.',
          );
        }
        match = (
          _world.entities.resolve(entityIndex),
          _a.valueAt(aDense),
          _b.valueAt(bDense),
          _c.valueAt(cDense),
          _d.valueAt(dDense),
        );
      }
      return match;
    } finally {
      _world.endQuery();
    }
  }

  (Entity, A, B, C, D) single() {
    final match = singleOrNull();
    if (match == null) {
      throw StateError(
        'Query4<$A, $B, $C, $D>.single: expected exactly one matching entity, '
        'found none.',
      );
    }
    return match;
  }
}
