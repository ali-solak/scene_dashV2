import '../entity/entity.dart';
import 'query_1.dart';

/// A system parameter that resolves to the one entity matching a single-component
/// query.
///
/// Use it instead of iterating a `Query1` whose match set is known to be exactly
/// one entity (a player, a camera rig, the level controller). It removes the
/// "pull one entity out of a bulk loop" boilerplate:
///
/// ```dart
/// void run(
///   @Query(requires: [Player, Mounted]) Single<SceneNode> player,
/// ) {
///   final node = player.value.node;
/// }
/// ```
///
/// Resolution happens on first access, is validated — a descriptive
/// [StateError] when zero or more than one entity matches — and is then
/// **cached for the rest of the run**: the generated system adapter calls
/// [beginRun] before each run, so every `.value`/[entity] access within one
/// system run sees the same resolution and only the first one walks the query.
/// (Deferred `Commands` can't change the match set mid-run anyway; an immediate
/// structural change made mid-run surfaces on the next run.)
///
/// Code that constructs a `Single` by hand (a hand-written `SystemAdapter`,
/// a test) owns that contract itself: call [beginRun] at the start of each
/// run, or stale state is served forever.
final class Single<A> {
  /// Wraps [query]; normally constructed by the generated system adapter.
  Single(this._query);

  final Query1<A> _query;

  bool _resolved = false;
  late Entity _entity;
  late A _value;

  /// Clears the cached resolution so the next access re-walks the query.
  /// The generated system adapter calls this before every run; call it
  /// yourself when driving a hand-constructed instance.
  void beginRun() => _resolved = false;

  void _resolve() {
    final (entity, value) = _query.single();
    _entity = entity;
    _value = value;
    _resolved = true;
  }

  /// The matching component value. Throws [StateError] unless exactly one entity
  /// matches.
  A get value {
    if (!_resolved) _resolve();
    return _value;
  }

  /// The matching entity. Throws [StateError] unless exactly one entity matches.
  Entity get entity {
    if (!_resolved) _resolve();
    return _entity;
  }
}

/// A system parameter that resolves to at most one entity matching a
/// single-component query.
///
/// Like [Single], but tolerates zero matches ([valueOrNull] returns `null`). It
/// still throws when more than one entity matches, so it never silently hides an
/// unexpected duplicate — including from [isPresent], which shares the same
/// validated resolution.
///
/// The resolution is cached per run exactly like [Single]: the generated
/// adapter calls [beginRun] before each run; hand-constructed instances must
/// do so themselves.
final class OptionalSingle<A> {
  /// Wraps [query]; normally constructed by the generated system adapter.
  OptionalSingle(this._query);

  final Query1<A> _query;

  bool _resolved = false;
  Entity? _entity;
  A? _value;

  /// Clears the cached resolution so the next access re-walks the query.
  /// The generated system adapter calls this before every run; call it
  /// yourself when driving a hand-constructed instance.
  void beginRun() => _resolved = false;

  void _resolve() {
    final match = _query.singleOrNull();
    _entity = match?.$1;
    _value = match?.$2;
    _resolved = true;
  }

  /// Whether exactly one entity matches the query. Throws [StateError] when
  /// more than one matches.
  bool get isPresent {
    if (!_resolved) _resolve();
    return _value != null;
  }

  /// The matching component value, or `null` when none match. Throws
  /// [StateError] when more than one entity matches.
  A? get valueOrNull {
    if (!_resolved) _resolve();
    return _value;
  }

  /// The matching entity, or `null` when none match. Throws [StateError] when
  /// more than one entity matches.
  Entity? get entityOrNull {
    if (!_resolved) _resolve();
    return _entity;
  }
}
