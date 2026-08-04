part of '../collectables.dart';

/// Tags any collectable entity.
final class Collectable implements Tag {
  const Collectable();
}

/// Tags a shield pickup specifically.
final class ShieldPickup implements Tag {
  const ShieldPickup();
}

/// The player's active shield. A component, not a resource, because there
/// could be two. Added with `removeAfter:`; presence is the damage gate and
/// `expiryOf<Shielded>` drives the HUD ring.
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
