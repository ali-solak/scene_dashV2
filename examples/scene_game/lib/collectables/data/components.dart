part of '../collectables.dart';

/// Tags any collectable entity.
final class Collectable implements Tag {
  const Collectable();
}

/// Tags a shield pickup specifically.
final class ShieldPickup implements Tag {
  const ShieldPickup();
}

/// The player's active shield — a condition on the player, not a resource
/// (the state doctrine's test: there could be two, one per shielded
/// entity). Pickup adds it with `removeAfter: shieldDuration`; re-pickup
/// refreshes; deflecting re-adds with the reduced deadline; presence is
/// the damage gate and `expiryOf<Shielded>` the HUD ring.
final class Shielded {
  const Shielded();
}

/// A pickup's visual state: node references plus the animation clock, one
/// component because one system writes them together (composites beat
/// fragments — fewer components per query, fewer sparse lookups).
final class ShieldPickupVisuals {
  ShieldPickupVisuals(this.glow);

  /// The pulsing/bobbing glow child (the physics-driven root is left alone).
  final Node glow;

  /// Seconds since spawn, driving the pulse and bob.
  double age = 0;
}
