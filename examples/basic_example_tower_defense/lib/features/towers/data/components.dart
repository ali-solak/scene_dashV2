part of '../towers.dart';

final class const Tower(final TowerKind kind);

final class Gun {
  final GameTimer cooldown = GameTimer(boltCooldownSeconds);
}

final class Pulser {
  final GameTimer cooldown = GameTimer(pulseCooldownSeconds);
}

final class const ShieldEmitter();

final class TowerBeam(final Node node, final UnlitMaterial material) {
  final GameTween<double> fade = GameTween.number(1, 0, beamSeconds)
    ..tick(beamSeconds);
}

final class PulseRing(final Node node, final UnlitMaterial material) {
  final GameTween<double> fade = GameTween.number(1, 0, pulseRingSeconds)
    ..tick(pulseRingSeconds);
}

final class const TowerGhost(
  final Node node,
  final PhysicallyBasedMaterial material,
);

final class BuildChoice {
  TowerKind kind = TowerKind.bolt;
  Refusal? refusal;
}
