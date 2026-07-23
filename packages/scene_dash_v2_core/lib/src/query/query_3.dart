import '../entity/entity.dart';
import '../storage/component_store.dart';
import '../storage/object_store.dart';
import '../world/world.dart';
import 'query.dart';

typedef Query3Callback<A, B, C> = void Function(Entity entity, A a, B b, C c);

typedef Query3UntilCallback<A, B, C> =
    bool Function(Entity entity, A a, B b, C c);

final class Query3<A, B, C> extends Query {
  @override
  String get debugLabel => 'query3<$A, $B, $C>';

  @override
  int get debugRowEstimate => Query.chooseDriver(_driverCandidates).length;

  final World _world;
  final ObjectComponentStore<A> _a;
  final ObjectComponentStore<B> _b;
  final ObjectComponentStore<C> _c;
  final List<ComponentStore> _withStores;
  final List<ComponentStore> _withoutStores;

  late final List<ComponentStore> _driverCandidates = <ComponentStore>[
    _a,
    _b,
    _c,
    ..._withStores,
  ];

  Query3(
    this._world,
    this._a,
    this._b,
    this._c,
    this._withStores,
    this._withoutStores,
  );

  void each(Query3Callback<A, B, C> callback) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    final driverIsC = identical(driver, _c);
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

        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }

        callback(
          _world.entities.resolve(entityIndex),
          _a.valueAt(aDense),
          _b.valueAt(bDense),
          _c.valueAt(cDense),
        );
      }
    } finally {
      _world.endQuery();
    }
  }

  void eachUntil(Query3UntilCallback<A, B, C> callback) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    final driverIsC = identical(driver, _c);
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

        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }

        if (!callback(
          _world.entities.resolve(entityIndex),
          _a.valueAt(aDense),
          _b.valueAt(bDense),
          _c.valueAt(cDense),
        )) {
          return;
        }
      }
    } finally {
      _world.endQuery();
    }
  }

  (Entity, A, B, C)? firstWhere(Query3UntilCallback<A, B, C> predicate) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    final driverIsC = identical(driver, _c);
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
        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }
        final entity = _world.entities.resolve(entityIndex);
        final a = _a.valueAt(aDense);
        final b = _b.valueAt(bDense);
        final c = _c.valueAt(cDense);
        if (predicate(entity, a, b, c)) return (entity, a, b, c);
      }
      return null;
    } finally {
      _world.endQuery();
    }
  }

  bool any(Query3UntilCallback<A, B, C> predicate) {
    var found = false;
    eachUntil((entity, a, b, c) {
      if (predicate(entity, a, b, c)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  bool get(Entity entity, Query3Callback<A, B, C> found) {
    if (!_world.isAlive(entity)) return false;
    final entityIndex = entity.index;
    final aDense = _a.denseIndexOf(entityIndex);
    if (aDense < 0) return false;
    final bDense = _b.denseIndexOf(entityIndex);
    if (bDense < 0) return false;
    final cDense = _c.denseIndexOf(entityIndex);
    if (cDense < 0) return false;
    if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
      return false;
    }
    found(entity, _a.valueAt(aDense), _b.valueAt(bDense), _c.valueAt(cDense));
    return true;
  }

  (A, B, C)? components(Entity entity) {
    if (!_world.isAlive(entity)) return null;
    final entityIndex = entity.index;
    final aDense = _a.denseIndexOf(entityIndex);
    if (aDense < 0) return null;
    final bDense = _b.denseIndexOf(entityIndex);
    if (bDense < 0) return null;
    final cDense = _c.denseIndexOf(entityIndex);
    if (cDense < 0) return null;
    if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
      return null;
    }
    return (_a.valueAt(aDense), _b.valueAt(bDense), _c.valueAt(cDense));
  }

  bool get isEmpty {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    final driverIsC = identical(driver, _c);
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        if ((driverIsA ? i : _a.denseIndexOf(entityIndex)) < 0) continue;
        if ((driverIsB ? i : _b.denseIndexOf(entityIndex)) < 0) continue;
        if ((driverIsC ? i : _c.denseIndexOf(entityIndex)) < 0) continue;
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
    var matches = 0;
    _world.beginQuery(this);
    try {
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        if ((driverIsA ? i : _a.denseIndexOf(entityIndex)) < 0) continue;
        if ((driverIsB ? i : _b.denseIndexOf(entityIndex)) < 0) continue;
        if ((driverIsC ? i : _c.denseIndexOf(entityIndex)) < 0) continue;
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

  (Entity, A, B, C)? singleOrNull() {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    final driverIsC = identical(driver, _c);
    _world.beginQuery(this);
    try {
      (Entity, A, B, C)? match;
      for (var i = 0; i < driver.length; i++) {
        final entityIndex = driver.entityIndexAt(i);
        final aDense = driverIsA ? i : _a.denseIndexOf(entityIndex);
        if (aDense < 0) continue;
        final bDense = driverIsB ? i : _b.denseIndexOf(entityIndex);
        if (bDense < 0) continue;
        final cDense = driverIsC ? i : _c.denseIndexOf(entityIndex);
        if (cDense < 0) continue;
        if (!Query.passesFilters(entityIndex, _withStores, _withoutStores)) {
          continue;
        }
        if (match != null) {
          throw StateError(
            'Query3<$A, $B, $C>.single: expected exactly one matching entity, '
            'found more than one.',
          );
        }
        match = (
          _world.entities.resolve(entityIndex),
          _a.valueAt(aDense),
          _b.valueAt(bDense),
          _c.valueAt(cDense),
        );
      }
      return match;
    } finally {
      _world.endQuery();
    }
  }

  (Entity, A, B, C) single() {
    final match = singleOrNull();
    if (match == null) {
      throw StateError(
        'Query3<$A, $B, $C>.single: expected exactly one matching entity, '
        'found none.',
      );
    }
    return match;
  }
}
