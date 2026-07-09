import 'component_store.dart';
import 'object_store.dart';
import 'tag_store.dart';

/// Maps a component [Type] to its single [ComponentStore].
///
/// Until code generation exists (Phase 2), stores are registered manually. The
/// registry is the source of truth queries and commands consult to find the
/// store for a component type.
final class StoreRegistry {
  final Map<Type, ComponentStore> _stores = <Type, ComponentStore>{};
  final List<ComponentStore> _all = <ComponentStore>[];

  /// All registered stores. Used by despawn to strip an entity from every
  /// store it might belong to.
  Iterable<ComponentStore> get all => _all;

  /// Every registered `(type, store)` pair, in registration order.
  ///
  /// The reverse view of the type-keyed map, for diagnostics that need to
  /// name what a store holds (`World.debugComponentsOf`). Allocates a record
  /// per pair — debug-only; runtime code uses [all] or the typed lookups.
  Iterable<(Type, ComponentStore)> get entries =>
      _stores.entries.map((entry) => (entry.key, entry.value));

  /// Registers [store] as the store for component type [T]. Throws if a store
  /// for [T] is already registered.
  void register<T>(ComponentStore store) {
    if (_stores.containsKey(T)) {
      throw StateError('A store for $T is already registered.');
    }
    _stores[T] = store;
    _all.add(store);
  }

  /// Returns the object store for [T], creating it with one map lookup when
  /// absent.
  ObjectComponentStore<T> ensureObject<T>() {
    final existing = _stores[T];
    if (existing != null) return existing as ObjectComponentStore<T>;
    final created = ObjectComponentStore<T>();
    _stores[T] = created;
    _all.add(created);
    return created;
  }

  /// Returns the tag store for [T], creating it with one map lookup when absent.
  TagStore ensureTag<T>() {
    final existing = _stores[T];
    if (existing != null) return existing as TagStore;
    final created = TagStore();
    _stores[T] = created;
    _all.add(created);
    return created;
  }

  /// Whether a store is registered for [type].
  bool isRegistered(Type type) => _stores.containsKey(type);

  /// The store registered for [type], or throws if none exists.
  ComponentStore require(Type type) {
    final store = _stores[type];
    if (store == null) {
      throw StateError(
        'No component store registered for $type. Register it before use.',
      );
    }
    return store;
  }

  /// The object store for component type [T].
  ObjectComponentStore<T> object<T>() => require(T) as ObjectComponentStore<T>;

  /// The tag store for tag type [T].
  TagStore tag<T>() => require(T) as TagStore;
}
