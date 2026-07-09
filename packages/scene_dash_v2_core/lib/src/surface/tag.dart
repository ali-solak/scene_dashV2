/// The marker for tag components — presence-only types with no data.
///
/// Implementing [Tag] routes a class to the bit-cheap `TagStore` instead of
/// an object store:
///
/// ```dart
/// final class PlayerTag implements Tag {}
///
/// world.spawn([PlayerTag(), Health(100)]);
/// world.query<Health>(require: [PlayerTag]);
/// ```
///
/// Tag types are the one kind of component whose store cannot be created
/// from a spawned instance (Dart cannot instantiate a generic store from a
/// runtime type), so register each tag once at install time —
/// `game.registerTag<PlayerTag>()` — before it appears in a spawn list.
abstract interface class Tag {}
