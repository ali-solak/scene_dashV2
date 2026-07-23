import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Quaternion, Vector2, Vector3;

import '../enemies/enemies.dart' show Brawler, Enemy, Mired;
import '../fx/barrier_visual.dart';
import '../fx/burning_visual.dart';
import '../fx/fire_gush.dart';
import '../fx/lava_pit_visual.dart';
import '../fx/wind_blast.dart';
import '../game/actors.dart';
import '../game/character_assets.dart';
import '../game/combat_math.dart';
import '../game/game_state.dart';
import '../game/score.dart';
import '../game/sets.dart';
import '../player/player.dart'
    show CastLeap, HitLanded, Knockback, PlayerMotion, windCastSeconds;
import '../world/data/assets.dart';

part 'data/components.dart';
part 'data/config.dart';
part 'data/resources.dart';
part 'systems/systems.dart';

void installSkills(GameBuilder game) {
  game
    // The leap is consumed by the next fixed step.
    ..configureEvent<CastLeap>(retainedUpdates: null)
    ..registerComponent<Burning>()
    ..registerComponent<BurnFlame>()
    ..registerComponent<LavaPit>()
    ..registerComponent<Barrier>()
    ..registerComponent<BarrierVisual>()
    ..registerComponent<PendingWindBlast>()
    // Fire causes one flinch when first applied.
    ..observe<Burning>(
      onAdd: (world, entity, _) => world.tryGet<Brawler>(entity)?.sinceHurt = 0,
    )
    ..world.insert(SkillBook())
    ..addSystem(Schedules.frameStart, buyUpgrades, writes: const {Health})
    ..addSystem(
      Schedules.fixedUpdate,
      castSkills,
      inSet: GameSets.actions,
      reads: const {Player, Enemy, Health, PlayerMotion, SceneTransform},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      firePendingWindBlast,
      inSet: GameSets.actions,
      reads: const {Player, Enemy, Health, SceneTransform},
      writes: const {PendingWindBlast},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      tickBurning,
      inSet: GameSets.actions,
      reads: const {Health},
      writes: const {Burning},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      tickLavaPits,
      inSet: GameSets.actions,
      reads: const {Enemy, Health, SceneTransform, Burning},
      writes: const {LavaPit},
      after: const [tickBurning],
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      tickBarriers,
      inSet: GameSets.actions,
      writes: const {Barrier},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.update,
      attachLavaVisuals,
      inSet: GameSets.logic,
      reads: const {LavaPit, SceneTransform},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateBurnFlames,
      inSet: GameSets.logic,
      reads: const {Burning, SceneNode},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateBarrierVisual,
      inSet: GameSets.logic,
      reads: const {Player, Barrier, SceneNode},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateLavaMaterials,
      inSet: GameSets.logic,
      reads: const {LavaPit, SceneNode},
      after: const [attachLavaVisuals],
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      OnEnter(GameStatus.fighting),
      resetSkills,
      reads: const {Player, LavaPit},
      runIf: freshRun,
    );
}
