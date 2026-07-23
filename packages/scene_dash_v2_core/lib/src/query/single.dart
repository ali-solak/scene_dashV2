import '../entity/entity.dart';
import 'query_1.dart';

final class Single<A> {
  Single(this._query);

  final Query1<A> _query;

  bool _resolved = false;
  late Entity _entity;
  late A _value;

  void beginRun() => _resolved = false;

  void _resolve() {
    final (entity, value) = _query.single();
    _entity = entity;
    _value = value;
    _resolved = true;
  }

  A get value {
    if (!_resolved) _resolve();
    return _value;
  }

  Entity get entity {
    if (!_resolved) _resolve();
    return _entity;
  }
}

final class OptionalSingle<A> {
  OptionalSingle(this._query);

  final Query1<A> _query;

  bool _resolved = false;
  Entity? _entity;
  A? _value;

  void beginRun() => _resolved = false;

  void _resolve() {
    final match = _query.singleOrNull();
    _entity = match?.$1;
    _value = match?.$2;
    _resolved = true;
  }

  bool get isPresent {
    if (!_resolved) _resolve();
    return _value != null;
  }

  A? get valueOrNull {
    if (!_resolved) _resolve();
    return _value;
  }

  Entity? get entityOrNull {
    if (!_resolved) _resolve();
    return _entity;
  }
}
