import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../../fx/anim.dart';
import '../../fx/particles.dart' as fx;
import '../../fx/particle_texture.dart';
import '../../common/bounds.dart';
import '../../common/camera_rig.dart';
import '../../common/sets.dart';
import '../../common/game_state.dart';
import '../../common/physics_layers.dart';
import '../player/data/config.dart';
import '../player/player.dart';
import '../rocks/data/config.dart';
import '../rocks/rocks.dart';
import 'data/config.dart';
import 'vfx/reticle_widget.dart';
import 'package:flutter_scene/physics.dart';

part 'data/components.dart';
part 'data/resources.dart';
part 'data/bundles.dart';
part 'vfx/vfx.dart';
part 'systems/systems.dart';
part 'vfx/charge_vfx.dart';
part 'vfx/impact_vfx.dart';
part 'vfx/reticle.dart';

void installProjectiles(GameBuilder game) {
  game
    ..registerComponent<Projectile>()
    ..registerComponent<Blaster>()
    ..registerComponent<LockOnReticle>()
    ..registerComponent<ChargePlasmaEmitter>()
    ..configureEvent<FirePressed>(retainedUpdates: null)
    ..configureEvent<FireReleased>(retainedUpdates: null)
    ..configureEvent<FireCanceled>(retainedUpdates: null)
    ..observe<LockOnReticle>(onRemove: disposeReticleModel)
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
    ..addSystem(
      Schedules.fixedUpdate,
      shootProjectiles,
      reads: {NodeRef},
      writes: {Projectile, Blaster, LockOnReticle},
      inSet: GameSets.actions,
      runIf: inState(GameStatus.playing),
    )
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
    ..addSystem(
      Schedules.update,
      updateProjectiles,
      reads: {NodeRef},
      writes: {Projectile, LockOnReticle},
    )
    ..addSystem(
      Schedules.update,
      updateChargeVisuals,
      reads: {Blaster, NodeRef},
      writes: {PlayerChargeVisuals, ChargePlasmaEmitter},
    )
    ..addSystem(
      Schedules.update,
      updateLockOnReticle,
      reads: {NodeRef, Blaster},
      writes: {LockOnReticle},
      after: [updateProjectiles],
    )
    ..addSystem(
      Schedules.shutdown,
      disposeLockOnReticle,
      writes: {LockOnReticle},
    );
}
