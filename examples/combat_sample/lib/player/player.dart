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

/// Installs the player: the lifted combat machine (`combat/combat.dart` —
/// its reference suite runs against that code unchanged), buffered
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
    // Per frame rather than on a state entry, and for the same reason the
    // enemies' attach is: the knight has to be standing in the clearing
    // during the TITLE screen, because the opening push-in has to have
    // something to arrive at. The system early-outs once bodied, so the
    // steady-state cost is one query.
    //
    // The attach is deferred (world.add), so no live write is declared —
    // the enemies' attach adds SceneNode to different entities in the same
    // frame, and neither system touches the other's rows.
    ..addSystem(
      Schedules.update,
      attachPlayerVisuals,
      inSet: GameSets.logic,
      reads: const {Player},
      runIf: hasResource<Scene>(),
    )
    // The run reset (boot + restart) is driven by rules' `startRun`, which
    // calls [resetPlayerRun] — one writer, so the player and enemy resets
    // don't collide in `OnEnter(fighting)`.
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
    // Fixed step, not update: it reads `justEntered(rolling)`, and a
    // machine edge is raised by `go` and lowered on the next tick — the
    // update schedule can miss it entirely. Deferred spawn only, so no
    // live write is declared.
    ..addSystem(
      Schedules.fixedUpdate,
      spawnPlayerFx,
      inSet: GameSets.actions,
      reads: const {Player, Fighter, PlayerMotion, SceneTransform},
      after: const [fighterDriver],
      runIf: hasResource<Scene>(),
    )
    // Fixed step, with the fighters: a per-FRAME sampler chasing
    // per-fixed-step bones records the same rung several times over at
    // high frame rates, which bunches the ribbon at its head. In
    // `actions` rather than `resolution` so set order alone keeps it off
    // `applyDamage`, which writes the Fighter it reads.
    ..addSystem(
      Schedules.fixedUpdate,
      updateBladeTrail,
      inSet: GameSets.actions,
      reads: const {Player, Fighter, BladeTrail},
      after: const [fighterDriver],
      runIf: hasResource<Scene>(),
    )
    // The hit path (applyDamage, clearBufferOnStagger) is registered by
    // the rules feature in GameSets.resolution — after every driver, by
    // set order alone.
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
      // `spawnPlayerFx` only READS Fighter (for the roll edge) and this
      // writes it, which the entity-blind detector calls a conflict even
      // though they cannot disagree. Ordering settles it.
      after: const [fighterDriver, spawnPlayerFx, updateBladeTrail],
      runIf: inState(GameStatus.fighting),
    )
    // Fixed-step, after resolution: the camera and the fighters advance on
    // the same clock — a per-frame camera chasing per-fixed-step positions
    // stair-steps into visible jitter.
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
