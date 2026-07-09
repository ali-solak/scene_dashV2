/// A type-keyed container of singleton application resources.
///
/// Resources are ordinary Dart objects (config, input state, timers, physics
/// worlds, ...). Each type has at most one instance, injected into systems via
/// the `@Resource()` annotation.
final class Resources {
  final Map<Type, Object> _resources = <Type, Object>{};

  /// Inserts or replaces the resource instance for type [T].
  void insert<T extends Object>(T resource) {
    _resources[T] = resource;
  }

  /// The resource of type [T]. Throws [StateError] if none is registered.
  T get<T extends Object>() {
    final resource = _resources[T];
    if (resource == null) {
      throw StateError('No resource of type $T has been inserted.');
    }
    return resource as T;
  }

  /// The resource of type [T], or `null` if none is registered.
  T? tryGet<T extends Object>() => _resources[T] as T?;

  /// The resource of type [T], inserting and returning `orElse()` when none
  /// is registered yet.
  ///
  /// For lazily-created state owned at its first use site (a scratch cache, a
  /// debug accumulator) where there is no natural plugin to insert it up
  /// front. The hit path is a single map lookup and calls nothing; ownership
  /// semantics are unchanged — a resource already present is returned as-is,
  /// never replaced.
  T getOrInsert<T extends Object>(T Function() orElse) {
    final existing = _resources[T];
    if (existing != null) return existing as T;
    final created = orElse();
    _resources[T] = created;
    return created;
  }

  /// Whether a resource of type [T] is registered.
  bool contains<T extends Object>() => _resources.containsKey(T);

  /// Removes the resource of type [T], returning it if present.
  T? remove<T extends Object>() => _resources.remove(T) as T?;

  /// Removes every resource. Used by `World.reset(keepResources: false)`;
  /// systems holding a resource reference keep their (now-orphaned) instance,
  /// so a full resource clear is only safe before re-initialization.
  void clear() => _resources.clear();
}
