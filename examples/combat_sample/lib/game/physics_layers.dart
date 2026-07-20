/// Physics collision-layer identity, shared across features (scene_game's
/// pattern). Phase 1 only needs the ground; fighter and hitbox bits arrive
/// with their features.
library;

abstract final class PhysicsLayers {
  static const int ground = 1 << 0;
  static const int fighter = 1 << 1;
}
