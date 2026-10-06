part of '../damage.dart';

final class Health(final double max) {
  late double current = max;
}

final class Shield(final double max) {
  late double current = max;
  double sinceHit = 0;
}

final class const Bounty(final int gold);

final class const Tint(final PhysicallyBasedMaterial material);

final class const ShieldBubble(
  final Node node,
  final PhysicallyBasedMaterial material,
);

final class const HitFlash();

final class const Pop() implements Tag;

final class const DamageDealt(final Entity target, final double amount);

final class const Destroyed(final Vector3 at, final int bounty);
