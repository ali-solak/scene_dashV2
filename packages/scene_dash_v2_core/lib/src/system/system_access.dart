/// Component types read and written by a system.
final class SystemAccess {
  /// Component types the system reads (queried but not in `writes`).
  final Set<Type> reads;

  /// Component types the system declares it writes.
  final Set<Type> writes;

  const SystemAccess({
    this.reads = const <Type>{},
    this.writes = const <Type>{},
  });

  /// Access that touches nothing.
  static const SystemAccess empty = SystemAccess();
}

/// Provides access data for a system.
abstract interface class SystemAccessProvider {
  /// The component access this system declares.
  SystemAccess get access;
}
