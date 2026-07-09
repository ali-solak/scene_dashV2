/// The component access a system declares: which component types it reads and
/// which it writes.
///
/// This is *diagnostic* metadata derived from `@Query(writes: ...)` and the
/// queried component types. Dart cannot prevent mutation through a value
/// declared read-only, so Scene-Dash does not attempt borrow checking — the
/// metadata is used only to detect likely ordering hazards between systems.
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

/// Implemented by system adapters that can report their [SystemAccess].
///
/// This is a *separate, optional* interface from `SystemAdapter`: generated
/// adapters always implement it. The schedule compiler treats adapters that do
/// not implement it as touching nothing — such a system can never be flagged,
/// so a hand-written adapter that touches component data should implement it
/// too and declare what it reads and writes (the built-in adapters all do).
/// Only adapters that touch no component data at all may safely omit it.
abstract interface class SystemAccessProvider {
  /// The component access this system declares.
  SystemAccess get access;
}
