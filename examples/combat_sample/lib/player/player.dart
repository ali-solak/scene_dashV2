import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Quaternion, Vector3, Vector4;

import '../enemies/enemies.dart'
    show Enemy, Brawler, BrawlPhase, telegraphSeconds;
import '../fx/dash_dust.dart';
import '../fx/sword_trail.dart';
import '../game/actors.dart';
import '../game/camera_rig.dart';
import '../game/character_assets.dart';
import '../game/game_state.dart';
import '../game/inputs.dart';
import '../game/sets.dart';
import '../world/data/arena.dart';
import '../world/data/config.dart' show characterModelYaw, characterScale;
import 'combat/combat.dart';

export '../game/actors.dart';
export 'combat/combat.dart';

part 'animation/animator.dart';
part 'data/components.dart';
part 'data/config.dart';
part 'data/bundles.dart';
part 'systems/systems.dart';

/// Installs the player: the lifted combat machine (`combat/combat.dart`,
/// whose reference suite runs against that code unchanged), buffered
/// roll/attack with the hold-to-commit heavy, stance locomotion, and
/// lock-on with the rig-driven camera.
void installPlayer(GameBuilder game) {
  game
    ..registerTag<Player>()
    ..registerComponent<Fighter>()
    ..registerComponent<PlayerMotion>()
    ..registerComponent<PlayerAnimator>()
    ..registerComponent<Knockback>()
    ..registerComponent<Target>()
    ..registerComponent<BladeTrail>()
    ..addSystem(Schedules.frameStart, ageCombatBuffer, reads: const {})
    ..addSystem(
      Schedules.startup,
      spawnPlayer,
      writes: const {Player, Fighter, PlayerMotion},
    )
    ..addSystem(
      Schedules.update,
      attachPlayerVisuals,
      inSet: GameSets.logic,
      reads: const {Player},
      runIf: hasResource<Scene>(),
    )
    // Run resets (boot + restart) go through rules' `startRun`, which calls
    // [resetPlayerRun]: one writer, so player and enemy resets don't collide.
    ..addSystem(
      Schedules.fixedUpdate,
      movePlayer,
      inSet: GameSets.movement,
      reads: const {Player, Fighter, Target},
      writes: const {PlayerMotion, SceneTransform, Knockback},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      fighterDriver,
      inSet: GameSets.actions,
      writes: const {Fighter},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      spawnPlayerFx,
      inSet: GameSets.actions,
      reads: const {Player, Fighter, PlayerMotion, SceneTransform},
      after: const [fighterDriver],
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      updateBladeTrail,
      inSet: GameSets.actions,
      reads: const {Player, Fighter, BladeTrail},
      after: const [fighterDriver],
      runIf: hasResource<Scene>(),
    )
    // The hit path (applyDamage, clearBufferOnStagger) is registered by the
    // rules feature in GameSets.resolution, after every driver by set order.
    ..addSystem(
      Schedules.fixedUpdate,
      lockOnSystem,
      inSet: GameSets.actions,
      reads: const {
        Player,
        Enemy,
        Health,
        PlayerMotion,
        SceneTransform,
        Target,
      },
      writes: const {Fighter},
      // `spawnPlayerFx` only reads Fighter and this writes it; the
      // entity-blind detector calls that a conflict, so order it explicitly.
      after: const [fighterDriver, spawnPlayerFx, updateBladeTrail],
      runIf: inState(GameStatus.fighting),
    )
    // Fixed-step, after resolution: a per-frame camera chasing
    // per-fixed-step positions stair-steps into visible jitter.
    ..addSystem(
      Schedules.fixedUpdate,
      updateCameraRig,
      inSet: GameSets.resolution,
      reads: const {Player, PlayerMotion, SceneTransform, Target},
    )
    ..addSystem(
      Schedules.update,
      updatePlayerAnimation,
      inSet: GameSets.logic,
      reads: const {Player, Fighter, PlayerMotion},
      writes: const {PlayerAnimator},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updatePlayerGhost,
      inSet: GameSets.logic,
      reads: const {Player, Fighter, SceneNode, Knockback},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateEnemyHighlights,
      inSet: GameSets.logic,
      reads: const {Player, Enemy, Target, Brawler, SceneNode},
      runIf: hasResource<Scene>(),
    );
}
