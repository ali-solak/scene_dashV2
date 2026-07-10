/// A resource the framework tears down when it drops the instance.
///
/// Implement it on a resource that owns something needing release — a
/// native handle, a stream, a bloc. No base class, no registration:
/// implementing the interface is the whole contract. The framework calls
/// [dispose] at exactly three points, once per instance — game shutdown
/// (every resource, reverse insertion order, so dependents die before
/// their dependencies), `World.reset(keepResources: false)` (the dropped
/// resources), and removal or replacement (the outgoing instance).
abstract interface class Disposable {
  void dispose();
}

/// A type-keyed container of singleton application resources.
///
/// Resources are ordinary Dart objects (config, input state, timers, physics
/// worlds, ...). Each type has at most one instance, injected into systems via
/// the `@Resource()` annotation. A resource implementing [Disposable] is
/// disposed by the framework when its instance is dropped.
final class Resources {
  // Insertion-ordered (Dart map literals are LinkedHashMaps) — [disposeAll]
  // relies on it to tear dependents down before their dependencies.
  final Map<Type, Object> _resources = <Type, Object>{};

  // Instances this container already disposed, by identity, so no framework
  // call site ever disposes twice — the same instance may sit under two type
  // keys, or leave and be re-inserted (which marks it live again).
  final Set<Object> _disposed = Set.identity();

  /// Inserts or replaces the resource instance for type [T]. A replaced
  /// instance is disposed (if [Disposable]); re-inserting the identical
  /// instance is a no-op for disposal.
  void insert<T extends Object>(T resource) {
    final outgoing = _resources[T];
    _resources[T] = resource;
    _disposed.remove(resource);
    if (outgoing != null && !identical(outgoing, resource)) {
      _dispose(outgoing);
    }
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
    _disposed.remove(created);
    return created;
  }

  /// Whether a resource of type [T] is registered.
  bool contains<T extends Object>() => _resources.containsKey(T);

  /// Every registered resource with its type key, in insertion order.
  /// Diagnostics surface — the inspector snapshot enumerates it; allocates
  /// a record per pair, so not for per-frame engine code.
  Iterable<(Type, Object)> get entries sync* {
    for (final entry in _resources.entries) {
      yield (entry.key, entry.value);
    }
  }

  /// Removes the resource of type [T], returning it if present. The removed
  /// instance is disposed (if [Disposable]) — removal is teardown, not an
  /// ownership transfer.
  T? remove<T extends Object>() {
    final removed = _resources.remove(T);
    if (removed != null) _dispose(removed);
    return removed as T?;
  }

  /// Removes every resource, disposing the [Disposable] ones in reverse
  /// insertion order — dependents die before their dependencies. Called by
  /// the framework at game shutdown and by
  /// `World.reset(keepResources: false)`; systems holding a resource
  /// reference keep their (now-orphaned) instance, so a full clear is only
  /// safe at teardown or before re-initialization.
  void disposeAll() {
    final values = _resources.values.toList();
    _resources.clear();
    for (var i = values.length - 1; i >= 0; i--) {
      _dispose(values[i]);
    }
  }

  void _dispose(Object resource) {
    if (resource is Disposable && _disposed.add(resource)) {
      resource.dispose();
    }
  }
}
