import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../fx/anim.dart';
import '../fx/particles.dart' as fx;
import '../fx/particle_texture.dart';
import '../game/bounds.dart';
import '../game/camera_rig.dart';
import '../game/sets.dart';
import '../game/game_state.dart';
import '../game/physics_layers.dart';
import '../player/data/config.dart';
import '../player/player.dart';
import '../rocks/data/config.dart';
import '../rocks/rocks.dart';
import 'data/config.dart';
import 'vfx/reticle_widget.dart';

part 'data/components.dart';
part 'data/resources.dart';
part 'data/bundles.dart';
part 'vfx/vfx.dart';
part 'systems/systems.dart';
part 'vfx/charge_vfx.dart';
part 'vfx/impact_vfx.dart';
part 'vfx/reticle.dart';

/// Installs the player's blaster, projectiles, charge/impact VFX and the
/// lock-on reticle. The feature owns the [Blaster] *component* and
/// attaches it to the player on every `OnEnter(playing)`; the HUD reads it
/// back through the world (`world.singleOrNull<Blaster>()`) — nothing is
/// constructed in `main` or threaded through parameters.
void installProjectiles(GameBuilder game) {
  game
    ..registerComponent<Projectile>()
    ..registerComponent<Blaster>()
    ..registerComponent<LockOnReticle>()
    ..registerComponent<ChargePlasmaEmitter>()
    ..configureEvent<FirePressed>(retainedUpdates: null)
    ..configureEvent<FireReleased>(retainedUpdates: null)
    ..configureEvent<FireCanceled>(retainedUpdates: null)
    // The reticle's model dies with the component on any removal path;
    // shutdown (which despawns nothing) closes it via disposeLockOnReticle.
    ..observe<LockOnReticle>(onRemove: disposeReticleModel)
    // The attach is deferred (world.add), so the declared write is the
    // feature-owned component; the player is found by tag, keeping this
    // clear of the player feature's SceneNode writes in the same enter.
    ..addSystem(
      OnEnter(GameStatus.playing),
      attachBlaster,
      reads: {Player},
      writes: {Blaster},
    )
    ..addSystem(
      OnEnter(GameStatus.playing),
      resetProjectilesOnRunStart,
      writes: {LockOnReticle},
    )
    ..addSystem(
      OnExit(GameStatus.playing),
      stopBlasterOnRunEnd,
      reads: {Blaster},
    )
    // Shooting reads the player position after the movement phase; the
    // charged-shot flash is a live reticle-component write.
    ..addSystem(
      Schedules.fixedUpdate,
      shootProjectiles,
      reads: {SceneNode},
      writes: {Projectile, Blaster, LockOnReticle},
      inSet: GameSets.actions,
      runIf: inState(GameStatus.playing),
    )
    // The spawns are deferred; the declared writes are feature-owned types.
    ..addSystem(
      Schedules.startup,
      spawnLockOnReticle,
      writes: {LockOnReticle},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.startup,
      spawnChargePlasma,
      writes: {ChargePlasmaEmitter},
      runIf: hasResource<Scene>(),
    )
    // The rock-hit reaction insert is deferred (world.add applies at the
    // command boundary); the live writes are the projectile and the
    // reticle's impact flash.
    ..addSystem(
      Schedules.update,
      updateProjectiles,
      reads: {SceneNode},
      writes: {Projectile, LockOnReticle},
    )
    ..addSystem(
      Schedules.update,
      updateChargeVisuals,
      reads: {Blaster, SceneNode},
      writes: {PlayerChargeVisuals, ChargePlasmaEmitter},
    )
    // Ordered after updateProjectiles: both write the reticle (flash set
    // vs. flash decay), and the ordering keeps a fresh impact flash from
    // being decayed in its own frame.
    ..addSystem(
      Schedules.update,
      updateLockOnReticle,
      reads: {SceneNode, Blaster},
      writes: {LockOnReticle},
      after: [updateProjectiles],
    )
    // Entities are not despawned at shutdown, so the reticle's model is
    // closed by a shutdown system rather than the removal observer.
    ..addSystem(
      Schedules.shutdown,
      disposeLockOnReticle,
      writes: {LockOnReticle},
    );
}
