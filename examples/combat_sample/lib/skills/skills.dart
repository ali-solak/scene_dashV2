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
    // castSkills → fighterDriver, both fighting-gated fixed systems one
    // step apart: unbounded retention so the leap can never be dropped —
    // not even by a pause opened the same instant as the cast. (The input
    // edges — SkillCast, the lock presses — ride the framework's default
    // retention, which is wide enough for fixed-step readers at any
    // realistic refresh rate.)
    ..configureEvent<CastLeap>(retainedUpdates: null)
    ..registerComponent<Burning>()
    ..registerComponent<BurnFlame>()
    ..registerComponent<LavaPit>()
    ..registerComponent<Barrier>()
    ..registerComponent<BarrierVisual>()
    ..registerComponent<PendingWindBlast>()
    // Fire/lava reads as landing with ONE flinch, on the catch — not a
    // stagger (that stunlocks a body in a pit, see `applyDamage`) and not
    // every tick (that held the reaction forever). Adding `Burning` fires
    // once; refreshing it each lava tick fires nothing, so this is exactly
    // the leading edge.
    ..observe<Burning>(
      onAdd: (world, entity, _) => world.tryGet<Brawler>(entity)?.sinceHurt = 0,
    )
    ..world.insert(SkillBook())
    // frameStart, like the restart request: buying happens while the menu
    // has the world paused, so it must not sit behind a `fighting` gate.
    ..addSystem(Schedules.frameStart, buyUpgrades, writes: const {Health})
    ..addSystem(
      Schedules.fixedUpdate,
      castSkills,
      inSet: GameSets.actions,
      reads: const {Player, Enemy, Health, PlayerMotion, SceneTransform},
      runIf: inState(GameStatus.fighting),
    )
    // Fires the deferred wind gust once its leap lands.
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
      // Burning is READ (never downgrade a gush's fire) and added
      // deferred, so it is not declared as a write.
      reads: const {Enemy, Health, SceneTransform, Burning},
      writes: const {LavaPit},
      after: const [tickBurning],
      runIf: inState(GameStatus.fighting),
    )
    // In `actions`, one set ahead of the resolution that zeroes the flare
    // on a block: gameplay owns the clock, the sphere only reads it.
    ..addSystem(
      Schedules.fixedUpdate,
      tickBarriers,
      inSet: GameSets.actions,
      writes: const {Barrier},
      runIf: inState(GameStatus.fighting),
    )
    // Deferred adds only — no live write declared (see the player's attach).
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
    // Deferred add/remove of BarrierVisual only — the Barrier itself is
    // read, never written (see the player's attach on why the empty
    // `writes:` is deliberate).
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
    );
}
