import '../entity/entity.dart';
import '../storage/component_store.dart';
import '../storage/object_store.dart';
import '../world/world.dart';
import 'query.dart';

/// Callback invoked once per matching entity for a single-component query.
typedef Query1Callback<A> = void Function(Entity entity, A a);

/// Callback for [Query1.eachUntil]: return `true` to keep iterating, `false`
/// to stop. The same shape doubles as the predicate of [Query1.firstWhere]
/// and [Query1.any], where `true` instead means "this row matches" — each
/// method documents which meaning applies.
typedef Query1UntilCallback<A> = bool Function(Entity entity, A a);

/// A cached query over one object component [A], with optional `with`/`without`
/// filters.
final class Query1<A> extends Query {
  final World _world;
  final ObjectComponentStore<A> _a;
  final List<ComponentStore> _withStores;
  final List<ComponentStore> _withoutStores;

  /// Stores considered when choosing the smallest iteration driver.
  late final List<ComponentStore> _driverCandidates = <ComponentStore>[
    _a,
    ..._withStores,
  ];

  Query1(this._world, this._a, this._withStores, this._withoutStores);

  /// Invokes [callback] for every live entity that has component [A] and
  /// satisfies the filters. The component value is passed directly; no
  /// allocations occur per entity.
  void each(Query1Callback<A> callback) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    _world.beginQuery();
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

  /// Invokes [callback] for matching entities exactly like [each], but stops
  /// as soon as [callback] returns `false`.
  ///
  /// The early-exit form of [each], for searches that do not need the whole
  /// match set — "find one free spawn point", "stop after the first target in
  /// range". Same driver selection, filters and iteration order as [each];
  /// allocation-free.
  void eachUntil(Query1UntilCallback<A> callback) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    _world.beginQuery();
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

  /// The first matching row for which [predicate] returns `true`, as an
  /// `(entity, value)` record, or `null` when no row satisfies it.
  ///
  /// **Inverted predicate:** `true` here means "this is the row I want"
  /// (like `Iterable.firstWhere`) — the *opposite* of an [eachUntil]
  /// callback, whose `true` means "keep going". Passing an [eachUntil]-style
  /// callback returns the first row it would have *continued past*.
  ///
  /// Cold-path convenience: allocates one record on a hit. Prefer [eachUntil]
  /// with write-through mutation in per-frame loops.
  (Entity, A)? firstWhere(Query1UntilCallback<A> predicate) {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    _world.beginQuery();
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

  /// Whether any matching row satisfies [predicate]. Stops at the first hit.
  ///
  /// Like [firstWhere] — and unlike an [eachUntil] callback — `true` from
  /// [predicate] means "this row matches". Allocates one small closure per
  /// call (it wraps [eachUntil]); use [eachUntil] directly in the very
  /// hottest loops.
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

  /// The component [A] on [entity], or `null` when [entity] is stale, lacks
  /// [A], or fails this query's `with`/`without` filters.
  ///
  /// The random-access counterpart to [each]: an O(1) sparse-set lookup that
  /// reaches one specific entity — a hit target, a lock-on — without scanning
  /// the whole query. The returned object is the live component, so mutating
  /// its fields writes through; this doubles as the mutable accessor.
  /// Allocation-free.
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

  /// The component [A] on [entity] as a one-field record, or `null` when
  /// [entity] is stale, lacks [A], or fails the filters — the record-returning
  /// twin of [get], with identical semantics.
  ///
  /// Exists so all query arities share one lookup shape (`Query2.components`
  /// returns `(A, B)` and so on). The record field is the live component, so
  /// mutating its fields writes through. Cold-path convenience: allocates a
  /// record; prefer [get] in per-frame loops.
  (A,)? components(Entity entity) {
    final a = get(entity);
    return a == null ? null : (a,);
  }

  /// Whether no live entity matches this query. Stops at the first match, so it
  /// is cheaper than counting; allocation-free.
  bool get isEmpty {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    _world.beginQuery();
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

  /// Resolves the single matching entity as `(entity, value)`, or `null` when
  /// none match. Throws [StateError] when more than one entity matches.
  ///
  /// One small record is allocated per match — intended for singleton queries
  /// (`Single`/`OptionalSingle`), not hot per-entity loops; use [each] there.
  (Entity, A)? singleOrNull() {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    _world.beginQuery();
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

  /// Resolves the single matching entity as `(entity, value)`. Throws
  /// [StateError] when zero or more than one entity matches. See [singleOrNull].
  (Entity, A) single() {
    final match = singleOrNull();
    if (match == null) {
      throw StateError(
        'Query1<$A>.single: expected exactly one matching entity, found none.',
      );
    }
    return match;
  }

  /// The exact number of matching entities. Scans the driver store;
  /// allocation-free. Cache it in a resource if you read it more than once
  /// per frame at scale.
  int count() {
    final driver = Query.chooseDriver(_driverCandidates);
    final driverIsA = identical(driver, _a);
    var matches = 0;
    _world.beginQuery();
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

  /// The number of entities the driver store currently holds. This is an upper
  /// bound on matches, not the exact match count.
  int get driverLength => Query.chooseDriver(_driverCandidates).length;
}
