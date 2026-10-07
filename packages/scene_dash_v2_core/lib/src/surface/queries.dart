/// Record based world queries.
library;

import '../entity/entity.dart';
import '../query/query_1.dart';
import '../query/query_2.dart';
import '../query/query_3.dart';
import '../query/query_4.dart';
import '../storage/component_store.dart';
import '../storage/object_store.dart';
import '../world/world.dart';
import 'game_builder.dart';

bool _noteTypes(World world, List<Type> types) {
  final host = world.runningSystem;
  if (host is EventCursorHost) host.noteQueriedTypes(types);
  return true;
}

Never _noMatch(String surface) =>
    throw StateError('$surface: no matching entity.');

/// A query over one component type.
final class QueryView1<A extends Object> {
  final World _world;
  final ObjectComponentStore<A> _a;
  final List<ComponentStore> _with;
  final List<ComponentStore> _without;

  late final Query1<A> _core = Query1<A>(_world, _a, _with, _without);

  QueryView1._(this._world, this._a, this._with, this._without);

  /// Builds the query.
  factory QueryView1(World world) {
    assert(_noteTypes(world, [A]));
    return QueryView1._(
      world,
      world.ensureObjectStore<A>(),
      const <ComponentStore>[],
      const <ComponentStore>[],
    );
  }

  int get revision {
    var sum = _a.revision;
    for (final store in _with) {
      sum += store.revision;
    }
    for (final store in _without) {
      sum += store.revision;
    }
    return sum;
  }

  QueryView1<A> having<T extends Object>() {
    assert(_noteTypes(_world, [T]));
    return QueryView1._(_world, _a, [
      ..._with,
      _world.ensureStore<T>(),
    ], _without);
  }

  QueryView1<A> without<T extends Object>() {
    assert(_noteTypes(_world, [T]));
    return QueryView1._(_world, _a, _with, [
      ..._without,
      _world.ensureStore<T>(),
    ]);
  }

  /// Calls [callback] for each match.
  void each(void Function(Entity entity, A a) callback) => _core.each(callback);

  /// Stops when [callback] returns false.
  void eachUntil(bool Function(Entity entity, A a) callback) =>
      _core.eachUntil(callback);

  /// Whether any match satisfies [test]. Stops at the first hit.
  bool any(bool Function(Entity entity, A a) test) => _core.any(test);

  /// The first match satisfying [test] as a record, or `null`.
  (Entity, A)? firstWhere(bool Function(Entity entity, A a) test) =>
      _core.firstWhere(test);

  /// Copies matching rows into a new list. Later structural changes do not
  /// change its membership, but the component objects remain live references.
  List<(Entity, A)> snapshot() {
    final rows = <(Entity, A)>[];
    _core.each((entity, a) => rows.add((entity, a)));
    return rows;
  }

  /// The first match, or `null` when nothing matches.
  (Entity, A)? get firstOrNull => _core.firstWhere((_, _) => true);

  /// The first match; throws when nothing matches.
  (Entity, A) get first => firstOrNull ?? _noMatch('query().first');

  A? get(Entity entity) => _core.get(entity);

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

/// A query over two component types.
final class QueryView2<A extends Object, B extends Object> {
  final World _world;
  final ObjectComponentStore<A> _a;
  final ObjectComponentStore<B> _b;
  final List<ComponentStore> _with;
  final List<ComponentStore> _without;

  late final Query2<A, B> _core = Query2<A, B>(_world, _a, _b, _with, _without);

  QueryView2._(this._world, this._a, this._b, this._with, this._without);

  /// Builds the query.
  factory QueryView2(World world) {
    assert(_noteTypes(world, [A, B]));
    return QueryView2._(
      world,
      world.ensureObjectStore<A>(),
      world.ensureObjectStore<B>(),
      const <ComponentStore>[],
      const <ComponentStore>[],
    );
  }

  int get revision {
    var sum = _a.revision + _b.revision;
    for (final store in _with) {
      sum += store.revision;
    }
    for (final store in _without) {
      sum += store.revision;
    }
    return sum;
  }

  QueryView2<A, B> having<T extends Object>() {
    assert(_noteTypes(_world, [T]));
    return QueryView2._(_world, _a, _b, [
      ..._with,
      _world.ensureStore<T>(),
    ], _without);
  }

  QueryView2<A, B> without<T extends Object>() {
    assert(_noteTypes(_world, [T]));
    return QueryView2._(_world, _a, _b, _with, [
      ..._without,
      _world.ensureStore<T>(),
    ]);
  }

  /// Calls [callback] for each match.
  void each(void Function(Entity entity, A a, B b) callback) =>
      _core.each(callback);

  /// Stops when [callback] returns false.
  void eachUntil(bool Function(Entity entity, A a, B b) callback) =>
      _core.eachUntil(callback);

  /// Whether any match satisfies [test]. Stops at the first hit.
  bool any(bool Function(Entity entity, A a, B b) test) => _core.any(test);

  /// The first match satisfying [test] as a record, or `null`.
  (Entity, A, B)? firstWhere(bool Function(Entity entity, A a, B b) test) =>
      _core.firstWhere(test);

  /// Copies matching rows into a new list with shared component references.
  List<(Entity, A, B)> snapshot() {
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

/// A query over three component types.
final class QueryView3<A extends Object, B extends Object, C extends Object> {
  final World _world;
  final ObjectComponentStore<A> _a;
  final ObjectComponentStore<B> _b;
  final ObjectComponentStore<C> _c;
  final List<ComponentStore> _with;
  final List<ComponentStore> _without;

  late final Query3<A, B, C> _core = Query3<A, B, C>(
    _world,
    _a,
    _b,
    _c,
    _with,
    _without,
  );

  QueryView3._(
    this._world,
    this._a,
    this._b,
    this._c,
    this._with,
    this._without,
  );

  /// Builds the query.
  factory QueryView3(World world) {
    assert(_noteTypes(world, [A, B, C]));
    return QueryView3._(
      world,
      world.ensureObjectStore<A>(),
      world.ensureObjectStore<B>(),
      world.ensureObjectStore<C>(),
      const <ComponentStore>[],
      const <ComponentStore>[],
    );
  }

  int get revision {
    var sum = _a.revision + _b.revision + _c.revision;
    for (final store in _with) {
      sum += store.revision;
    }
    for (final store in _without) {
      sum += store.revision;
    }
    return sum;
  }

  QueryView3<A, B, C> having<T extends Object>() {
    assert(_noteTypes(_world, [T]));
    return QueryView3._(_world, _a, _b, _c, [
      ..._with,
      _world.ensureStore<T>(),
    ], _without);
  }

  QueryView3<A, B, C> without<T extends Object>() {
    assert(_noteTypes(_world, [T]));
    return QueryView3._(_world, _a, _b, _c, _with, [
      ..._without,
      _world.ensureStore<T>(),
    ]);
  }

  /// Calls [callback] for each match.
  void each(void Function(Entity entity, A a, B b, C c) callback) =>
      _core.each(callback);

  /// Stops when [callback] returns false.
  void eachUntil(bool Function(Entity entity, A a, B b, C c) callback) =>
      _core.eachUntil(callback);

  /// Whether any match satisfies [test]. Stops at the first hit.
  bool any(bool Function(Entity entity, A a, B b, C c) test) => _core.any(test);

  /// The first match satisfying [test] as a record, or `null`.
  (Entity, A, B, C)? firstWhere(
    bool Function(Entity entity, A a, B b, C c) test,
  ) => _core.firstWhere(test);

  /// Copies matching rows into a new list with shared component references.
  List<(Entity, A, B, C)> snapshot() {
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

/// A query over four component types.
final class QueryView4<
  A extends Object,
  B extends Object,
  C extends Object,
  D extends Object
> {
  final World _world;
  final ObjectComponentStore<A> _a;
  final ObjectComponentStore<B> _b;
  final ObjectComponentStore<C> _c;
  final ObjectComponentStore<D> _d;
  final List<ComponentStore> _with;
  final List<ComponentStore> _without;

  late final Query4<A, B, C, D> _core = Query4<A, B, C, D>(
    _world,
    _a,
    _b,
    _c,
    _d,
    _with,
    _without,
  );

  QueryView4._(
    this._world,
    this._a,
    this._b,
    this._c,
    this._d,
    this._with,
    this._without,
  );

  /// Builds the query.
  factory QueryView4(World world) {
    assert(_noteTypes(world, [A, B, C, D]));
    return QueryView4._(
      world,
      world.ensureObjectStore<A>(),
      world.ensureObjectStore<B>(),
      world.ensureObjectStore<C>(),
      world.ensureObjectStore<D>(),
      const <ComponentStore>[],
      const <ComponentStore>[],
    );
  }

  int get revision {
    var sum = _a.revision + _b.revision + _c.revision + _d.revision;
    for (final store in _with) {
      sum += store.revision;
    }
    for (final store in _without) {
      sum += store.revision;
    }
    return sum;
  }

  QueryView4<A, B, C, D> having<T extends Object>() {
    assert(_noteTypes(_world, [T]));
    return QueryView4._(_world, _a, _b, _c, _d, [
      ..._with,
      _world.ensureStore<T>(),
    ], _without);
  }

  QueryView4<A, B, C, D> without<T extends Object>() {
    assert(_noteTypes(_world, [T]));
    return QueryView4._(_world, _a, _b, _c, _d, _with, [
      ..._without,
      _world.ensureStore<T>(),
    ]);
  }

  /// Calls [callback] for each match.
  void each(void Function(Entity entity, A a, B b, C c, D d) callback) =>
      _core.each(callback);

  /// Stops when [callback] returns false.
  void eachUntil(bool Function(Entity entity, A a, B b, C c, D d) callback) =>
      _core.eachUntil(callback);

  /// Whether any match satisfies [test]. Stops at the first hit.
  bool any(bool Function(Entity entity, A a, B b, C c, D d) test) =>
      _core.any(test);

  /// The first match satisfying [test] as a record, or `null`.
  (Entity, A, B, C, D)? firstWhere(
    bool Function(Entity entity, A a, B b, C c, D d) test,
  ) => _core.firstWhere(test);

  /// Copies matching rows into a new list with shared component references.
  List<(Entity, A, B, C, D)> snapshot() {
    final rows = <(Entity, A, B, C, D)>[];
    _core.each((entity, a, b, c, d) => rows.add((entity, a, b, c, d)));
    return rows;
  }

  /// The first match, or `null` when nothing matches.
  (Entity, A, B, C, D)? get firstOrNull =>
      _core.firstWhere((_, _, _, _, _) => true);

  /// The first match; throws when nothing matches.
  (Entity, A, B, C, D) get first => firstOrNull ?? _noMatch('query4().first');

  /// The single match, or `null` when nothing matches; throws when more
  /// than one entity matches.
  (Entity, A, B, C, D)? get singleOrNull => _core.singleOrNull();

  /// The single match; throws when zero or several match.
  (Entity, A, B, C, D) get single =>
      singleOrNull ?? _noMatch('query4().single');

  /// Whether no entity matches. Stops at the first hit; allocation-free.
  bool get isEmpty => _core.isEmpty;

  /// Whether any entity matches. Stops at the first hit; allocation-free.
  bool get isNotEmpty => !_core.isEmpty;

  /// The exact number of matches. Allocation-free.
  int count() => _core.count();
}

/// Record query methods for [World].
extension WorldRecordQueries on World {
  /// A record query over one component type; see [QueryView1].
  QueryView1<A> query<A extends Object>() => QueryView1<A>(this);

  /// A record query over two component types; see [QueryView2].
  QueryView2<A, B> query2<A extends Object, B extends Object>() =>
      QueryView2<A, B>(this);

  /// A record query over three component types; see [QueryView3].
  QueryView3<A, B, C>
  query3<A extends Object, B extends Object, C extends Object>() =>
      QueryView3<A, B, C>(this);

  /// A record query over four component types; see [QueryView4].
  QueryView4<A, B, C, D> query4<
    A extends Object,
    B extends Object,
    C extends Object,
    D extends Object
  >() => QueryView4<A, B, C, D>(this);
}
