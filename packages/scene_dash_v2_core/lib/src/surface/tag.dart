/// A marker for presence-only components.
///
/// Implementing [Tag] uses a compact tag store, created on first spawn:
///
/// ```dart
/// final class PlayerTag implements Tag {}
///
/// world.spawn([PlayerTag(), Health(100)]);
/// world.query<Health>().having<PlayerTag>();
/// ```
abstract interface class Tag {}
