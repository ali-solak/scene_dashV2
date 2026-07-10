import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../fx/anim.dart';
import '../fx/instanced_pool.dart';
import '../game/camera_rig.dart';
import '../game/sets.dart';
import '../game/game_state.dart';
import '../game/physics_layers.dart';
import '../player/data/config.dart';
import '../player/player.dart';
import '../rocks/data/config.dart';
import '../rocks/rocks.dart';
import '../world/data/config.dart';
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
/// lock-on reticle. The feature owns and inserts the [Blaster]; the HUD
/// reads it back through the world (`world.resource<Blaster>()`) — nothing
/// is constructed in `main` or threaded through parameters.
void installProjectiles(GameBuilder game) {
  game.world
    ..insert(Blaster())
    ..insert(ImpactVfx())
    ..insert(LockOnReticle());
  game
    ..registerComponent<Projectile>()
    ..configureEvent<FirePressed>(retainedUpdates: null)
    ..configureEvent<FireReleased>(retainedUpdates: null)
    ..configureEvent<FireCanceled>(retainedUpdates: null)
    ..addSystem(
      OnEnter(GameStatus.playing),
      resetProjectilesOnRunStart,
      reads: const {},
    )
    ..addSystem(
      OnExit(GameStatus.playing),
      stopBlasterOnRunEnd,
      reads: const {},
    )
    // Shooting reads the player position after the movement phase.
    ..addSystem(
      Schedules.fixedUpdate,
      shootProjectiles,
      reads: {SceneNode},
      writes: {Projectile},
      inSet: GameSets.actions,
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(
      Schedules.startup,
      spawnImpactVfx,
      reads: const {},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.startup,
      spawnLockOnReticle,
      reads: const {},
      runIf: hasResource<Scene>(),
    )
    // The rock-hit reaction insert is deferred (world.add applies at the
    // command boundary), so only the live Projectile mutation is a write.
    ..addSystem(
      Schedules.update,
      updateProjectiles,
      reads: {SceneNode},
      writes: {Projectile},
    )
    ..addSystem(
      Schedules.update,
      updateChargeVisuals,
      writes: {PlayerChargeVisuals},
    )
    ..addSystem(Schedules.update, updateImpactVfx, reads: const {})
    ..addSystem(Schedules.update, updateLockOnReticle, reads: {SceneNode})
    ..addSystem(Schedules.shutdown, disposeLockOnReticle, reads: const {});
}
