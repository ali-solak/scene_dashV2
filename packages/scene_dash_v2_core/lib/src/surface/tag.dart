/// A marker for presence-only components.
///
/// Implementing [Tag] uses a compact tag store. Register each tag before
/// spawning it:
///
/// ```dart
/// final class PlayerTag implements Tag {}
///
/// game.registerTag<PlayerTag>();
/// world.spawn([PlayerTag(), Health(100)]);
/// ```
abstract interface class Tag {}
