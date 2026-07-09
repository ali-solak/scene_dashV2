import '../entity/entity.dart';
import '../storage/component_store.dart';
import '../storage/object_store.dart';
import '../world/world.dart';
import 'query.dart';

/// Callback invoked once per matching entity for a two-component query.
typedef Query2Callback<A, B> = void Function(Entity entity, A a, B b);

/// Callback for [Query2.eachUntil]: return `true` to keep iterating, `false`
/// to stop. The same shape doubles as the predicate of [Query2.firstWhere]
/// and [Query2.any], where `true` instead means "this row matches" — each
/// method documents which meaning applies.
typedef Query2UntilCallback<A, B> = bool Function(Entity entity, A a, B b);

/// A cached query over two object components [A] and [B], with optional
/// `with`/`without` filters.
final class Query2<A, B> extends Query {
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

  Query2(
    this._world,
    this._a,
    this._b,
    this._withStores,
    this._withoutStores,
  );

  /// Invokes [callback] for every live entity that has both [A] and [B] and
  /// satisfies the filters.
  void each(Query2Callback<A, B> callback) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    _world.beginQuery();
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

  /// Invokes [callback] for matching entities exactly like [each], but stops
  /// as soon as [callback] returns `false`.
  ///
  /// The early-exit form of [each]; same driver selection, filters and
  /// iteration order. Allocation-free.
  void eachUntil(Query2UntilCallback<A, B> callback) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    _world.beginQuery();
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

  /// The first matching row for which [predicate] returns `true`, as an
  /// `(entity, a, b)` record, or `null` when no row satisfies it.
  ///
  /// **Inverted predicate:** `true` here means "this is the row I want" —
  /// the *opposite* of an [eachUntil] callback, whose `true` means "keep
  /// going".
  ///
  /// Cold-path convenience: allocates one record on a hit. Prefer [eachUntil]
  /// with write-through mutation in per-frame loops.
  (Entity, A, B)? firstWhere(Query2UntilCallback<A, B> predicate) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    _world.beginQuery();
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

  /// Whether any matching row satisfies [predicate]. Stops at the first hit.
  ///
  /// Like [firstWhere] — and unlike an [eachUntil] callback — `true` from
  /// [predicate] means "this row matches". Allocates one small closure per
  /// call (it wraps [eachUntil]); use [eachUntil] directly in the very
  /// hottest loops.
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

  /// Invokes [found] with [entity]'s [A] and [B] when [entity] is live, has
  /// both, and satisfies the filters; returns whether it matched.
  ///
  /// The random-access counterpart to [each]: an O(1) lookup of one specific
  /// entity without scanning. It takes a callback rather than returning a
  /// record so hot paths stay allocation-free; the passed components are the
  /// live objects, so mutating their fields writes through.
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

  /// [entity]'s [A] and [B] as a record, or `null` when [entity] is stale,
  /// misses either component, or fails the filters — the record-returning
  /// twin of [get], with identical semantics.
  ///
  /// The record fields are the live components, so mutating their fields
  /// writes through. Cold-path convenience: allocates a record; prefer [get]
  /// in per-frame loops.
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

  /// Whether no live entity matches this query. Stops at the first match;
  /// allocation-free.
  bool get isEmpty {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    _world.beginQuery();
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

  /// The exact number of matching entities. Scans the driver store;
  /// allocation-free. Cache it in a resource if you read it more than once
  /// per frame at scale.
  int count() {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    var matches = 0;
    _world.beginQuery();
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

  /// Resolves the single matching entity as `(entity, a, b)`, or `null` when
  /// none match. Throws [StateError] when more than one entity matches. See
  /// `Query1.singleOrNull` for allocation notes.
  (Entity, A, B)? singleOrNull() {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    final driverIsB = identical(driver, _b);
    _world.beginQuery();
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

  /// Resolves the single matching entity as `(entity, a, b)`. Throws
  /// [StateError] when zero or more than one entity matches.
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
