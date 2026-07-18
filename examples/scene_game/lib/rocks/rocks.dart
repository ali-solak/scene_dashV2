import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../fx/particles.dart' as fx;
import '../fx/particle_texture.dart';
import '../game/bounds.dart';
import '../game/game_state.dart';
import '../game/physics_layers.dart';
import 'data/config.dart';

part 'data/components.dart';
part 'data/resources.dart';
part 'data/bundles.dart';
part 'vfx/vfx.dart';
part 'systems/systems.dart';

/// Installs the rocks feature — v1's plugin body without the class. The
/// spawner is a run-scoped process entity (spawned on every
/// `OnEnter(playing)`). Flame trails are one shared world-space particle
/// emitter at the scene root (upstream particles simulate in emitter-local
/// space, so per-rock emitters cannot trail — see [FlameTrailShape]);
/// `updateFlameTrails` feeds it the flaming rocks' positions and the scene
/// advances the simulation.
void installRocks(GameBuilder game) {
  game
    ..registerTag<Rock>()
    ..registerTag<Flaming>()
    ..registerComponent<RockSpawner>()
    ..registerComponent<FlameTrailEmitter>()
    // The tag is the single source of the flaming look; runtime ignition
    // is one `world.add(rock, const Flaming())`. The observers own the
    // full payload: material swap plus trail-emitter attach/detach.
    ..observe<Flaming>(onAdd: igniteRock, onRemove: extinguishRock)
    // Invariant: no reaction ⇒ shell hidden, on every removal path.
    ..observe<RockHitReaction>(onRemove: clearHitShell)
    ..addSystem(
      OnEnter(GameStatus.playing),
      spawnRockSpawner,
      writes: {RockSpawner},
    )
    // The spawn itself is deferred to the command boundary, so the
    // declared writes are the feature-owned types. Scene-gated like
    // spawnPlayer: the bundle builds GPU meshes, so headless boots skip
    // the system (rock tests spawn their own stand-ins).
    ..addSystem(
      Schedules.fixedUpdate,
      spawnRocks,
      writes: {Rock, Flaming, RockSpawner},
      runIf: hasResource<Scene>().and(inState(GameStatus.playing)),
    )
    // Off-ramp cleanup is the bundle's DespawnOutside part (world feature).
    // The spawn is deferred; the declared write is the feature-owned type.
    ..addSystem(
      Schedules.startup,
      spawnFlameTrailEmitter,
      writes: {FlameTrailEmitter},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateFlameTrails,
      reads: {SceneNode},
      writes: {FlameTrailEmitter},
    )
    // The reaction itself is read-only here: its removeAfter deadline is
    // the lifecycle, so the system never mutates or removes it.
    ..addSystem(
      Schedules.update,
      updateRockHitReactions,
      reads: {RockHitReaction},
      writes: {RockVisuals},
    );
}
