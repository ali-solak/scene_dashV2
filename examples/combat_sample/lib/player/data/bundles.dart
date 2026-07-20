part of '../player.dart';

/// The player's spawn list: pure data — the graybox body is attached
/// scene-side by [attachPlayerVisuals], so headless suites drive the same
/// spawn path.
List<Object> playerBundle() => [
      const Player(),
      Fighter(),
      Health(playerMaxHealth),
      Knockback(),
      // Spawns at the arena rim looking at the center (facing pi = -Z).
      PlayerMotion()..facing = math.pi,
      SceneTransform(playerSpawnX, 0, playerSpawnZ),
    ];
