/// Physics collision-layer identity, shared across features.
library;

/// Collision-group membership bits, so query results can be classified by
/// layer. The overlap queries enforce the mask against
/// `Collider.collisionLayer` on every hit.
abstract final class PhysicsLayers {
  static const int player = 1 << 0;
  static const int platform = 1 << 1;
  static const int rock = 1 << 2;
  static const int collectable = 1 << 3;
}
