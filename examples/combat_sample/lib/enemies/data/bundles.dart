part of '../enemies.dart';

/// A barbarian's spawn list: pure data, body attached scene-side (the
/// same headless-first shape as the player). [index] alternates the
/// circle direction so a pack flanks instead of stacking; [health] and
/// [power] are the wave's scaling, and [giant] marks the one that grows.
List<Object> enemyBundle(
  double x,
  double z, {
  required int index,
  double? health,
  double power = 1,
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
    giant: giant,
  ),
  SceneTransform(x, 0, z),
];
