/// A resource that needs cleanup.
abstract interface class Disposable {
  void dispose();
}

/// Failures reported after all cleanup callbacks have been attempted.
/// Original exceptions and stack traces are retained in disposal order.
final class CleanupException implements Exception {
  CleanupException(Iterable<({Object error, StackTrace stackTrace})> errors)
    : failures = List.unmodifiable([
        for (final failure in errors)
          if (failure.error is CleanupException)
            ...(failure.error as CleanupException).failures
          else
            failure,
      ]);

  final List<({Object error, StackTrace stackTrace})> failures;

  @override
  String toString() =>
      'CleanupException: ${failures.length} failure(s): '
      '${failures.map((f) => f.error).join('; ')}';
}

/// Stores one resource per type.
final class Resources {
  // Keeps disposal order predictable.
  final Map<Type, Object> _resources = <Type, Object>{};

  // Weak identity tracking prevents duplicate disposal without retaining
  // every replaced resource for the lifetime of this collection.
  final Expando<bool> _disposed = Expando<bool>('disposed resource');

  /// Inserts or replaces the resource instance for type [T]. A replaced
  /// instance is disposed (if [Disposable]); re-inserting the identical
  /// instance is a no-op for disposal.
  void insert<T extends Object>(T resource) {
    final outgoing = _resources[T];
    _resources[T] = resource;
    if (resource is Disposable) _disposed[resource] = null;
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
    if (created is Disposable) _disposed[created] = null;
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

  /// Removes and disposes every resource in reverse order. Attempts all
  /// disposals before reporting failures in a [CleanupException].
  void disposeAll() {
    final values = _resources.values.toList();
    _resources.clear();
    final failures = <({Object error, StackTrace stackTrace})>[];
    for (var i = values.length - 1; i >= 0; i--) {
      try {
        _dispose(values[i]);
      } catch (error, stackTrace) {
        failures.add((error: error, stackTrace: stackTrace));
      }
    }
    if (failures.isNotEmpty) throw CleanupException(failures);
  }

  void _dispose(Object resource) {
    if (resource is Disposable && _disposed[resource] != true) {
      _disposed[resource] = true;
      resource.dispose();
    }
  }
}
