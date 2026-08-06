part of '../collectables.dart';

final class Collectable implements Tag {
  const Collectable();
}

final class ShieldPickup implements Tag {
  const ShieldPickup();
}

final class Shielded {
  const Shielded();
}

final class ShieldPickupVisuals {
  ShieldPickupVisuals(this.glow);

  final Node glow;

  double age = 0;
}
