import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Quaternion, Vector2, Vector3;

import '../enemies/enemies.dart' show Enemy;
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
import '../player/player.dart' show HitLanded, PlayerMotion;
import '../world/data/assets.dart';

part 'data/components.dart';
part 'data/config.dart';
part 'data/resources.dart';
part 'systems/systems.dart';

/// Installs what points buy: three castable skills and the vitality
/// upgrade.
///
/// Every skill deals its damage by emitting [HitLanded] — the same event
/// a sword swing emits — so kills, scoring, knockback, hitstop and the
/// death path are the rules feature's, unchanged. The casts run in
/// `GameSets.actions`, one set ahead of resolution, so a skill's damage
/// lands on the step it was cast.
///
/// The visuals (cone of flame, lava crust and embers, dust ring, the
/// fire that rides a burning body) are all
/// scene-gated, so the whole feature is testable headless.
void installSkills(GameBuilder game) {
  game
    ..registerComponent<Burning>()
    ..registerComponent<BurnFlame>()
    ..registerComponent<LavaPit>()
    ..registerComponent<Barrier>()
    ..registerComponent<BarrierVisual>()
    ..world.insert(SkillBook())
    // frameStart, like the restart request: buying happens while the menu
    // has the world paused, so it must not sit behind a `fighting` gate.
    ..addSystem(
      Schedules.frameStart,
      buyUpgrades,
      writes: const {Health},
    )
    ..addSystem(
      Schedules.fixedUpdate,
      castSkills,
      inSet: GameSets.actions,
      reads: const {Player, Enemy, Health, PlayerMotion, SceneTransform},
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
