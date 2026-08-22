part of '../towers.dart';

final class Tower {
  final GameTimer cooldown = GameTimer(towerCooldownSeconds);
}

final class TowerBeam(final Node node, final UnlitMaterial material) {
  final GameTween<double> fade = GameTween.number(1, 0, beamSeconds)
    ..tick(beamSeconds);
}
