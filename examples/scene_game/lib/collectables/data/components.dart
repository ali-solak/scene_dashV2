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

/// Per-pickup animation/lifetime state (only its age so far).
final class ShieldPickupState {
  double age = 0;
}

/// Direct references to a pickup's visual child nodes, animated in place.
final class ShieldPickupVisuals {
  const ShieldPickupVisuals(this.glow);

  /// The pulsing/bobbing glow child (the physics-driven root is left alone).
  final Node glow;
}
