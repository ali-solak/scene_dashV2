part of '../enemies.dart';

/// Builds enemy spawn components.
List<Object> enemyBundle(
  double x,
  double z, {
  required int index,
  double? health,
  double power = 1,
  double tempo = 1,
  bool giant = false,
}) => [
  const Enemy(),
  Health(health ?? enemyMaxHealth),
  Knockback(),
  Brawler(
    slot: index,
    circleDirection: index.isEven ? 1 : -1,
    wobbleSeed: index * 2.4,
    power: power,
    tempo: tempo,
    giant: giant,
  ),
  SceneTransform(x, 0, z),
];
