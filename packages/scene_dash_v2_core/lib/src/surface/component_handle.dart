import '../entity/entity.dart';
import '../storage/component_store.dart';
import '../storage/object_store.dart';
import '../storage/tag_store.dart';
import '../world/world.dart';
import 'game_builder.dart';
import 'tag.dart';

final class ComponentHandle<T extends Object> {
  final World _world;
  ComponentStore? _store;
  int _resolvedAtCount = -1;
  bool _settled = false;

  ComponentHandle(this._world) {
    assert(() {
      final host = _world.runningSystem;
      if (host is EventCursorHost) host.noteQueriedTypes([T]);
      return true;
    }());
  }

  ComponentStore? _resolve() {
    if (_settled) return _store;
    final stores = _world.stores;
    if (_resolvedAtCount == stores.count) return _store;
    _resolvedAtCount = stores.count;
    final exact = stores.lookup(T);
    if (exact != null) {
      _settled = true;
      return _store = exact;
    }
    if (<T>[] is List<Tag>) return _store = null;
    final supertype = stores.supertypeStoreOf<T>();
    if (supertype != null) return _store = supertype;
    _settled = true;
    return _store = stores.ensureObject<T>();
  }

  T? of(Entity entity) {
    if (!_world.entities.isAlive(entity)) return null;
    final store = _resolve();
    if (store is ObjectComponentStore<T>) return store.valueOf(entity.index);
    final value = store?.payloadOf(entity.index);
    return value is T ? value : null;
  }

  T get(Entity entity) {
    final value = of(entity);
    if (value == null) {
      throw StateError(
        _world.entities.isAlive(entity)
            ? '${entity.label} does not have component $T.'
            : 'Cannot get $T from stale ${entity.label}.',
      );
    }
    return value;
  }

  bool has(Entity entity) {
    if (!_world.entities.isAlive(entity)) return false;
    final store = _resolve();
    if (store == null) return false;
    if (store is TagStore || store is ObjectComponentStore<T>) {
      return store.containsIndex(entity.index);
    }
    return store.payloadOf(entity.index) is T;
  }
}
