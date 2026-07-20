import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Quaternion, Vector3, Vector4;

import '../game/actors.dart';
import '../game/camera_rig.dart';
import '../game/physics_layers.dart';
import '../game/character_assets.dart';
import '../game/game_state.dart';
import '../game/sets.dart';
import '../hud/health_bar_widget.dart';
import '../world/data/arena.dart';
import '../world/data/config.dart' show characterModelYaw, characterScale;

export '../game/actors.dart' show Health;

part 'animation/animator.dart';
part 'data/components.dart';
part 'data/config.dart';
part 'data/bundles.dart';
part 'systems/systems.dart';

/// Installs the barbarians: the brawl machine (approach/circle/telegraph/
/// swing/recover/staggered/dying), the aggro-token coordinator, pack
/// locomotion, and the material tells (telegraph emissive, death
/// dissolve). Stagger and death themselves arrive through the rules
/// feature's `applyDamage`.
void installEnemies(GameBuilder game) {
  game
    ..registerTag<Enemy>()
    ..registerComponent<Health>()
    ..registerComponent<Knockback>()
    ..registerComponent<Brawler>()
    ..registerComponent<AggroCoordinator>()
    ..registerComponent<BrawlerVisuals>()
    ..registerComponent<EnemyAnimator>()
    ..registerComponent<EnemyHealthBar>()
    ..registerComponent<Ragdoll>()
    ..registerComponent<ModelSlot>()
    ..registerComponent<Dissolving>()
    // A despawned barbarian hands its pooled model back, so the next
    // wave can borrow it (imported skinned models cannot be cloned).
    ..observe<ModelSlot>(onRemove: releaseEnemyModel)
    ..addSystem(
      Schedules.startup,
      spawnEnemies,
      writes: const {Enemy, Health, Brawler, AggroCoordinator},
    )
    // Per frame, not once: waves field barbarians all run long, and each
    // new one needs a body. The system skips anyone already bodied, so
    // the steady-state cost is one query. Deferred adds only — no live
    // write declared (see the player's attach).
    ..addSystem(
      Schedules.update,
      attachEnemyVisuals,
      inSet: GameSets.logic,
      reads: const {Enemy, Brawler},
      runIf: hasResource<Scene>(),
    )
    // The encounter reset (boot + restart) is driven by rules' `startRun`
    // via [resetEncounter] — one writer, so it doesn't collide with the
    // player reset in `OnEnter(fighting)`.
    ..addSystem(
      Schedules.fixedUpdate,
      moveBrawlers,
      inSet: GameSets.enemyMovement,
      reads: const {Player, Enemy},
      writes: const {Brawler, SceneTransform, Knockback},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      brawlerDriver,
      inSet: GameSets.actions,
      reads: const {Player, Enemy, Health, SceneTransform},
      writes: const {Brawler},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      coordinateAggro,
      inSet: GameSets.actions,
      reads: const {Player, Enemy, Health, SceneTransform},
      writes: const {AggroCoordinator, Brawler},
      after: const [brawlerDriver],
      runIf: inState(GameStatus.fighting),
    )
    // Death → Rapier: registered before the material/death system, which
    // orders itself after it.
    ..addSystem(
      Schedules.update,
      launchRagdolls,
      inSet: GameSets.logic,
      reads: const {Enemy, Brawler, Knockback, SceneNode},
      writes: const {Ragdoll, EnemyAnimator},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      settleRagdolls,
      inSet: GameSets.logic,
      reads: const {Enemy},
      writes: const {Ragdoll, EnemyAnimator},
      after: const [launchRagdolls],
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateBrawlerMaterials,
      inSet: GameSets.logic,
      reads: const {Enemy, Brawler, Dissolving},
      writes: const {BrawlerVisuals},
      after: const [launchRagdolls],
      runIf: hasResource<Scene>(),
    )
    // After BOTH ragdoll systems. The launch no longer freezes the
    // skeleton (the death clip has to play), so the freeze arrives from
    // `settleRagdolls` once the body has come to rest — and this mapper
    // has to run after it to see `frozen` and leave the final pose alone.
    ..addSystem(
      Schedules.update,
      updateEnemyAnimation,
      inSet: GameSets.logic,
      reads: const {Enemy, Brawler},
      writes: const {EnemyAnimator},
      after: const [launchRagdolls, settleRagdolls],
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateGiantGrowth,
      inSet: GameSets.logic,
      reads: const {Enemy, Brawler, Transforming},
      writes: const {BrawlerVisuals},
      after: const [updateBrawlerMaterials],
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateHealthBars,
      inSet: GameSets.logic,
      reads: const {Enemy, Brawler, Health, SceneTransform},
      writes: const {EnemyHealthBar},
      runIf: hasResource<Scene>(),
    );
}
