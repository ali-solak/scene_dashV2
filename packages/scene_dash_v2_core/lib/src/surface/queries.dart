/// The record-query surface: `world.query<A>()`, `query2`, `query3`,
/// `query4` (pinned decision D1) over the internal arity classes.
///
/// `each` is the primary spelling (D9) — callback parameters, zero
/// allocation, `return` as continue, `eachUntil` as break. Every query is
/// also an iterable of records through [records] (`(Entity, A)`,
/// `(Entity, A, B)`, …) at the cost of a small per-row allocation. Verbs
/// follow Dart conventions: `isEmpty`/`isNotEmpty`, predicate `any`/
/// `firstWhere`/`eachUntil` with multi-arg callbacks, and the row verbs
/// `first`, `firstOrNull`, `single`, `singleOrNull`, `count`.
///
/// Construction is a typed site: it registers the queried component stores
/// (which also materializes parked spawn-list parts of those types) and, in
/// debug mode, notes the types against the running system's declared access
/// for the drift check.
library;

import '../entity/entity.dart';
import '../query/query_1.dart';
import '../query/query_2.dart';
import '../query/query_3.dart';
import '../query/query_4.dart';
import '../storage/component_store.dart';
import '../world/world.dart';
import 'game_builder.dart';
import 'spawning.dart';

/// Resolves `require:`/`exclude:` filter types to their stores, with
/// guidance when a type was never registered (filters take runtime `Type`
/// objects, so they cannot register stores themselves).
List<ComponentStore> _filterStores(World world, List<Type> types) {
  if (types.isEmpty) return const <ComponentStore>[];
  final stores = <ComponentStore>[];
  for (final type in types) {
    if (!world.stores.isRegistered(type)) {
      throw StateError(
        'query(require/exclude: [$type]): no store is registered for '
        '$type. Filters cannot create stores from a Type object; register '
        'it once at install time (registerComponent<$type>() / '
        'registerTag<$type>()) or use the type in a spawn/typed call '
        'first.',
      );
    }
    stores.add(world.stores.require(type));
  }
  return stores;
}

void _noteTypes(World world, List<Type> types) {
  final host = world.runningSystem;
  if (host is EventCursorHost) host.noteQueriedTypes(types);
}

Never _noMatch(String surface) =>
    throw StateError('$surface: no matching entity.');

/// A 1-type record query; see the library docs for the surface contract.
final class QueryView1<A extends Object> {
  final Query1<A> _core;

  QueryView1._(this._core);

  /// Builds the query; a typed site — queried stores register lazily.
  factory QueryView1(
    World world, {
    List<Type> require = const <Type>[],
    List<Type> exclude = const <Type>[],
  }) {
    _noteTypes(world, [A, ...require, ...exclude]);
    final queue = SpawnQueue.of(world);
    return QueryView1._(
      Query1<A>(
        world,
        queue.ensureStore<A>(),
        _filterStores(world, require),
        _filterStores(world, exclude),
      ),
    );
  }

  /// Invokes [callback] once per match — the primary, zero-allocation
  /// spelling. `return` inside the callback continues with the next match.
  void each(void Function(Entity entity, A a) callback) =>
      _core.each(callback);

  /// Like [each], but stops as soon as [callback] returns `false` — the
  /// break-capable form.
  void eachUntil(bool Function(Entity entity, A a) callback) =>
      _core.eachUntil(callback);

  /// Whether any match satisfies [test]. Stops at the first hit.
  bool any(bool Function(Entity entity, A a) test) => _core.any(test);

  /// The first match satisfying [test] as a record, or `null`.
  (Entity, A)? firstWhere(bool Function(Entity entity, A a) test) =>
      _core.firstWhere(test);

  /// The matches as records, in iteration order — the for-loop spelling;
  /// allocates one record per row.
  Iterable<(Entity, A)> get records {
    final rows = <(Entity, A)>[];
    _core.each((entity, a) => rows.add((entity, a)));
    return rows;
  }

  /// The first match, or `null` when nothing matches.
  (Entity, A)? get firstOrNull => _core.firstWhere((_, _) => true);

  /// The first match; throws when nothing matches.
  (Entity, A) get first => firstOrNull ?? _noMatch('query().first');

  /// The single match, or `null` when nothing matches; throws when more
  /// than one entity matches.
  (Entity, A)? get singleOrNull => _core.singleOrNull();

  /// The single match; throws when zero or several match.
  (Entity, A) get single => singleOrNull ?? _noMatch('query().single');

  /// Whether no entity matches. Stops at the first hit; allocation-free.
  bool get isEmpty => _core.isEmpty;

  /// Whether any entity matches. Stops at the first hit; allocation-free.
  bool get isNotEmpty => !_core.isEmpty;

  /// The exact number of matches. Allocation-free.
  int count() => _core.count();
}

/// A 2-type record query; see the library docs for the surface contract.
final class QueryView2<A extends Object, B extends Object> {
  final Query2<A, B> _core;

  QueryView2._(this._core);

  /// Builds the query; a typed site — queried stores register lazily.
  factory QueryView2(
    World world, {
    List<Type> require = const <Type>[],
    List<Type> exclude = const <Type>[],
  }) {
    _noteTypes(world, [A, B, ...require, ...exclude]);
    final queue = SpawnQueue.of(world);
    return QueryView2._(
      Query2<A, B>(
        world,
        queue.ensureStore<A>(),
        queue.ensureStore<B>(),
        _filterStores(world, require),
        _filterStores(world, exclude),
      ),
    );
  }

  /// Invokes [callback] once per match — the primary, zero-allocation
  /// spelling. `return` inside the callback continues with the next match.
  void each(void Function(Entity entity, A a, B b) callback) =>
      _core.each(callback);

  /// Like [each], but stops as soon as [callback] returns `false` — the
  /// break-capable form.
  void eachUntil(bool Function(Entity entity, A a, B b) callback) =>
      _core.eachUntil(callback);

  /// Whether any match satisfies [test]. Stops at the first hit.
  bool any(bool Function(Entity entity, A a, B b) test) => _core.any(test);

  /// The first match satisfying [test] as a record, or `null`.
  (Entity, A, B)? firstWhere(bool Function(Entity entity, A a, B b) test) =>
      _core.firstWhere(test);

  /// The matches as records, in iteration order — the for-loop spelling;
  /// allocates one record per row.
  Iterable<(Entity, A, B)> get records {
    final rows = <(Entity, A, B)>[];
    _core.each((entity, a, b) => rows.add((entity, a, b)));
    return rows;
  }

  /// The first match, or `null` when nothing matches.
  (Entity, A, B)? get firstOrNull => _core.firstWhere((_, _, _) => true);

  /// The first match; throws when nothing matches.
  (Entity, A, B) get first => firstOrNull ?? _noMatch('query2().first');

  /// The single match, or `null` when nothing matches; throws when more
  /// than one entity matches.
  (Entity, A, B)? get singleOrNull => _core.singleOrNull();

  /// The single match; throws when zero or several match.
  (Entity, A, B) get single => singleOrNull ?? _noMatch('query2().single');

  /// Whether no entity matches. Stops at the first hit; allocation-free.
  bool get isEmpty => _core.isEmpty;

  /// Whether any entity matches. Stops at the first hit; allocation-free.
  bool get isNotEmpty => !_core.isEmpty;

  /// The exact number of matches. Allocation-free.
  int count() => _core.count();
}

/// A 3-type record query; see the library docs for the surface contract.
final class QueryView3<A extends Object, B extends Object, C extends Object> {
  final Query3<A, B, C> _core;

  QueryView3._(this._core);

  /// Builds the query; a typed site — queried stores register lazily.
  factory QueryView3(
    World world, {
    List<Type> require = const <Type>[],
    List<Type> exclude = const <Type>[],
  }) {
    _noteTypes(world, [A, B, C, ...require, ...exclude]);
    final queue = SpawnQueue.of(world);
    return QueryView3._(
      Query3<A, B, C>(
        world,
        queue.ensureStore<A>(),
        queue.ensureStore<B>(),
        queue.ensureStore<C>(),
        _filterStores(world, require),
        _filterStores(world, exclude),
      ),
    );
  }

  /// Invokes [callback] once per match — the primary, zero-allocation
  /// spelling. `return` inside the callback continues with the next match.
  void each(void Function(Entity entity, A a, B b, C c) callback) =>
      _core.each(callback);

  /// Like [each], but stops as soon as [callback] returns `false` — the
  /// break-capable form.
  void eachUntil(bool Function(Entity entity, A a, B b, C c) callback) =>
      _core.eachUntil(callback);

  /// Whether any match satisfies [test]. Stops at the first hit.
  bool any(bool Function(Entity entity, A a, B b, C c) test) => _core.any(test);

  /// The first match satisfying [test] as a record, or `null`.
  (Entity, A, B, C)? firstWhere(bool Function(Entity entity, A a, B b, C c) test) =>
      _core.firstWhere(test);

  /// The matches as records, in iteration order — the for-loop spelling;
  /// allocates one record per row.
  Iterable<(Entity, A, B, C)> get records {
    final rows = <(Entity, A, B, C)>[];
    _core.each((entity, a, b, c) => rows.add((entity, a, b, c)));
    return rows;
  }

  /// The first match, or `null` when nothing matches.
  (Entity, A, B, C)? get firstOrNull => _core.firstWhere((_, _, _, _) => true);

  /// The first match; throws when nothing matches.
  (Entity, A, B, C) get first => firstOrNull ?? _noMatch('query3().first');

  /// The single match, or `null` when nothing matches; throws when more
  /// than one entity matches.
  (Entity, A, B, C)? get singleOrNull => _core.singleOrNull();

  /// The single match; throws when zero or several match.
  (Entity, A, B, C) get single => singleOrNull ?? _noMatch('query3().single');

  /// Whether no entity matches. Stops at the first hit; allocation-free.
  bool get isEmpty => _core.isEmpty;

  /// Whether any entity matches. Stops at the first hit; allocation-free.
  bool get isNotEmpty => !_core.isEmpty;

  /// The exact number of matches. Allocation-free.
  int count() => _core.count();
}

/// A 4-type record query; see the library docs for the surface contract.
final class QueryView4<A extends Object, B extends Object, C extends Object, D extends Object> {
  final Query4<A, B, C, D> _core;

  QueryView4._(this._core);

  /// Builds the query; a typed site — queried stores register lazily.
  factory QueryView4(
    World world, {
    List<Type> require = const <Type>[],
    List<Type> exclude = const <Type>[],
  }) {
    _noteTypes(world, [A, B, C, D, ...require, ...exclude]);
    final queue = SpawnQueue.of(world);
    return QueryView4._(
      Query4<A, B, C, D>(
        world,
        queue.ensureStore<A>(),
        queue.ensureStore<B>(),
        queue.ensureStore<C>(),
        queue.ensureStore<D>(),
        _filterStores(world, require),
        _filterStores(world, exclude),
      ),
    );
  }

  /// Invokes [callback] once per match — the primary, zero-allocation
  /// spelling. `return` inside the callback continues with the next match.
  void each(void Function(Entity entity, A a, B b, C c, D d) callback) =>
      _core.each(callback);

  /// Like [each], but stops as soon as [callback] returns `false` — the
  /// break-capable form.
  void eachUntil(bool Function(Entity entity, A a, B b, C c, D d) callback) =>
      _core.eachUntil(callback);

  /// Whether any match satisfies [test]. Stops at the first hit.
  bool any(bool Function(Entity entity, A a, B b, C c, D d) test) => _core.any(test);

  /// The first match satisfying [test] as a record, or `null`.
  (Entity, A, B, C, D)? firstWhere(bool Function(Entity entity, A a, B b, C c, D d) test) =>
      _core.firstWhere(test);

  /// The matches as records, in iteration order — the for-loop spelling;
  /// allocates one record per row.
  Iterable<(Entity, A, B, C, D)> get records {
    final rows = <(Entity, A, B, C, D)>[];
    _core.each((entity, a, b, c, d) => rows.add((entity, a, b, c, d)));
    return rows;
  }

  /// The first match, or `null` when nothing matches.
  (Entity, A, B, C, D)? get firstOrNull => _core.firstWhere((_, _, _, _, _) => true);

  /// The first match; throws when nothing matches.
  (Entity, A, B, C, D) get first => firstOrNull ?? _noMatch('query4().first');

  /// The single match, or `null` when nothing matches; throws when more
  /// than one entity matches.
  (Entity, A, B, C, D)? get singleOrNull => _core.singleOrNull();

  /// The single match; throws when zero or several match.
  (Entity, A, B, C, D) get single => singleOrNull ?? _noMatch('query4().single');

  /// Whether no entity matches. Stops at the first hit; allocation-free.
  bool get isEmpty => _core.isEmpty;

  /// Whether any entity matches. Stops at the first hit; allocation-free.
  bool get isNotEmpty => !_core.isEmpty;

  /// The exact number of matches. Allocation-free.
  int count() => _core.count();
}

/// The record-query verbs on [World] (pinned decision D1).
extension WorldRecordQueries on World {
  /// A record query over one component type; see [QueryView1].
  QueryView1<A> query<A extends Object>({
    List<Type> require = const <Type>[],
    List<Type> exclude = const <Type>[],
  }) =>
      QueryView1<A>(this, require: require, exclude: exclude);

  /// A record query over two component types; see [QueryView2].
  QueryView2<A, B> query2<A extends Object, B extends Object>({
    List<Type> require = const <Type>[],
    List<Type> exclude = const <Type>[],
  }) =>
      QueryView2<A, B>(this, require: require, exclude: exclude);

  /// A record query over three component types; see [QueryView3].
  QueryView3<A, B, C>
      query3<A extends Object, B extends Object, C extends Object>({
    List<Type> require = const <Type>[],
    List<Type> exclude = const <Type>[],
  }) =>
          QueryView3<A, B, C>(this, require: require, exclude: exclude);

  /// A record query over four component types; see [QueryView4].
  QueryView4<A, B, C, D> query4<A extends Object, B extends Object,
          C extends Object, D extends Object>({
    List<Type> require = const <Type>[],
    List<Type> exclude = const <Type>[],
  }) =>
      QueryView4<A, B, C, D>(this, require: require, exclude: exclude);
}
