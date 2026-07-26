/// A resource that needs cleanup.
abstract interface class Disposable {
  void dispose();
}

/// Stores one resource per type.
final class Resources {
  // Keeps disposal order predictable.
  final Map<Type, Object> _resources = <Type, Object>{};

  // Prevents duplicate disposal.
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

  /// Creates [T] when missing and returns the stored value.
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

  /// Resources with their type keys.
  Iterable<(Type, Object)> get entries sync* {
    for (final entry in _resources.entries) {
      yield (entry.key, entry.value);
    }
  }

  /// Resource values in insertion order.
  Iterable<Object> get values => _resources.values;

  /// Removes and disposes [T].
  T? remove<T extends Object>() {
    final removed = _resources.remove(T);
    if (removed != null) _dispose(removed);
    return removed as T?;
  }

  /// Removes and disposes every resource in reverse order.
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
