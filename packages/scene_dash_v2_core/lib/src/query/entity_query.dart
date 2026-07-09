import '../entity/entity.dart';
import '../storage/component_store.dart';
import '../world/world.dart';
import 'query.dart';

/// Callback invoked once per matching entity for an entity-only query.
typedef EntityQueryCallback = void Function(Entity entity);

/// Callback for [EntityQuery.eachUntil]: return `true` to keep iterating,
/// `false` to stop. The same shape doubles as the predicate of
/// [EntityQuery.firstWhere] and [EntityQuery.any], where `true` instead means
/// "this entity matches" — each method documents which meaning applies.
typedef EntityQueryUntilCallback = bool Function(Entity entity);

/// A query over entities themselves — no component values — for match sets
/// defined entirely by tags and filters.
///
/// `Query1<A>` hands each match's component to the callback, so it needs an
/// object component to drive. When a system only needs *which* entities carry
/// a tag ("everything marked `Enemy`", "all `Invulnerable` entities"), there
/// is no component to name; this is that query. The Bevy equivalent is
/// `Query<Entity, With<Enemy>>`.
///
/// ```dart
/// @System()
/// void expireInvulnerability(
///   @Query(requires: [Invulnerable]) EntityQuery shielded,
///   Commands commands,
/// ) {
///   shielded.each((entity) => commands.remove<Invulnerable>(entity));
/// }
/// ```
///
/// At least one `requires` type is mandatory — it is what the iteration drives
/// from (the smallest required store, like every other query). Iteration is
/// allocation-free; [count] is an exact match count (a full scan of the
/// driver, honestly O(driver length) — cache it in a resource if you read it
/// more than once per frame at scale).
final class EntityQuery extends Query {
  final World _world;
  final List<ComponentStore> _withStores;
  final List<ComponentStore> _withoutStores;

  EntityQuery(this._world, this._withStores, this._withoutStores)
    : assert(
        _withStores.isNotEmpty,
        'EntityQuery needs at least one required type to drive iteration.',
      );

  /// Invokes [callback] for every live entity that satisfies the filters.
  void each(EntityQueryCallback callback) {
    final driver = Query.chooseDriver(_withStores);
    _world.beginQuery();
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

  /// Invokes [callback] for matching entities exactly like [each], but stops
  /// as soon as [callback] returns `false`.
  ///
  /// The early-exit form of [each]; same driver selection, filters and
  /// iteration order. Allocation-free.
  void eachUntil(EntityQueryUntilCallback callback) {
    final driver = Query.chooseDriver(_withStores);
    _world.beginQuery();
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

  /// The first matching entity for which [predicate] returns `true`, or
  /// `null` when none satisfies it.
  ///
  /// **Inverted predicate:** `true` here means "this is the entity I want" —
  /// the *opposite* of an [eachUntil] callback, whose `true` means "keep
  /// going". No component-value record to build, so unlike the `QueryN`
  /// variants this allocates nothing beyond the returned handle.
  Entity? firstWhere(EntityQueryUntilCallback predicate) {
    final driver = Query.chooseDriver(_withStores);
    _world.beginQuery();
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

  /// Whether any matching entity satisfies [predicate]. Stops at the first
  /// hit.
  ///
  /// Like [firstWhere] — and unlike an [eachUntil] callback — `true` from
  /// [predicate] means "this entity matches". Allocates one small closure per
  /// call (it wraps [eachUntil]); use [eachUntil] directly in the very
  /// hottest loops.
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

  /// Whether live [entity] currently matches this query's filters — the
  /// random-access counterpart to [each]. O(1), allocation-free.
  bool contains(Entity entity) {
    if (!_world.isAlive(entity)) return false;
    return Query.passesFilters(entity.index, _withStores, _withoutStores);
  }

  /// Whether no live entity matches. Stops at the first match;
  /// allocation-free.
  bool get isEmpty {
    final driver = Query.chooseDriver(_withStores);
    _world.beginQuery();
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

  /// The exact number of matching entities. Scans the driver store;
  /// allocation-free.
  int count() {
    final driver = Query.chooseDriver(_withStores);
    var matches = 0;
    _world.beginQuery();
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
