import 'component_store.dart';
import 'object_store.dart';
import 'store_membership.dart';
import 'tag_store.dart';

/// Maps component types to stores.
final class StoreRegistry {
  final Map<Type, ComponentStore> _stores = <Type, ComponentStore>{};
  final List<ComponentStore> _all = <ComponentStore>[];

  void Function(Type type, ComponentStore store)? onCreated;

  final StoreMembership membership = StoreMembership();

  final Map<Type, ComponentStore> _supertypeStores = <Type, ComponentStore>{};
  final Map<Type, int> _unresolvedAtCount = <Type, int>{};

  /// All registered stores. Used by despawn to strip an entity from every
  /// store it might belong to.
  Iterable<ComponentStore> get all => _all;

  /// Stores with their component types.
  Iterable<(Type, ComponentStore)> get entries =>
      _stores.entries.map((entry) => (entry.key, entry.value));

  /// Registers [store] as the store for component type [T]. Throws if a store
  /// for [T] is already registered.
  void register<T>(ComponentStore store) {
    if (_stores.containsKey(T)) {
      throw StateError('A store for $T is already registered.');
    }
    _add(T, store);
  }

  void _add(Type type, ComponentStore store) {
    store.attachMembership(membership, _all.length);
    _stores[type] = store;
    _all.add(store);
    onCreated?.call(type, store);
  }

  /// Returns the object store for [T], creating it with one map lookup when
  /// absent.
  ObjectComponentStore<T> ensureObject<T>() {
    final existing = _stores[T];
    if (existing != null) return existing as ObjectComponentStore<T>;
    final created = ObjectComponentStore<T>();
    _add(T, created);
    return created;
  }

  /// Returns the tag store for [T], creating it with one map lookup when absent.
  TagStore ensureTag<T>() {
    final existing = _stores[T];
    if (existing != null) return existing as TagStore;
    final created = TagStore();
    _add(T, created);
    return created;
  }

  TagStore ensureTagByType(Type type) {
    final existing = _stores[type];
    if (existing != null) return existing as TagStore;
    final created = TagStore();
    _add(type, created);
    return created;
  }

  int get count => _all.length;

  ComponentStore? supertypeStoreAccepting(Object part) {
    final type = part.runtimeType;
    final cached = _supertypeStores[type];
    if (cached != null || _unresolvedAtCount[type] == _all.length) {
      return cached;
    }
    for (final store in _all) {
      if (store.accepts(part)) return _supertypeStores[type] = store;
    }
    _unresolvedAtCount[type] = _all.length;
    return null;
  }

  ComponentStore? supertypeStoreOf<T>() {
    final cached = _supertypeStores[T];
    if (cached != null || _unresolvedAtCount[T] == _all.length) return cached;
    for (final store in _all) {
      if (store.holdsSubtype<T>()) return _supertypeStores[T] = store;
    }
    _unresolvedAtCount[T] = _all.length;
    return null;
  }

  ComponentStore storeAt(int id) => _all[id];

  /// Whether a store is registered for [type].
  bool isRegistered(Type type) => _stores.containsKey(type);

  ComponentStore? lookup(Type type) => _stores[type];

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
