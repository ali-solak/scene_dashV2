import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../../fx/anim.dart';
import '../../fx/particles.dart' as fx;
import '../../fx/particle_texture.dart';
import '../../common/bounds.dart';
import '../../common/game_state.dart';
import '../../common/physics_layers.dart';
import '../../common/sets.dart';
import '../player/data/config.dart';
import '../player/player.dart';
import 'data/config.dart';
import 'package:flutter_scene/physics.dart';

part 'data/components.dart';
part 'data/resources.dart';
part 'data/bundles.dart';
part 'vfx/vfx.dart';
part 'systems/systems.dart';

void installCollectables(GameBuilder game) {
  game.world.insert(PickupLanes());
  game
    ..registerTag<Collectable>()
    ..registerTag<ShieldPickup>()
    ..registerComponent<Shielded>()
    ..observe<Shielded>(onAdd: shieldGained, onRemove: shieldLost)
    ..addSystem(
      OnEnter(GameStatus.playing),
      resetCollectablesOnRunStart,
      writes: {Shielded},
    )
    ..addSystem(
      Schedules.fixedUpdate,
      spawnShieldPickups,
      writes: {Collectable, ShieldPickup},
      runIf: hasResource<Scene>()
          .and(inState(GameStatus.playing))
          .and(every(shieldPickupInterval)),
    )
    ..addSystem(
      Schedules.update,
      animateShieldPickups,
      writes: {ShieldPickupVisuals},
    )
    ..addSystem(
      Schedules.update,
      collectShieldPickups,
      reads: {NodeRef},
      writes: {Shielded},
      inSet: GameSets.logic,
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(
      Schedules.update,
      updateShieldVisuals,
      reads: {Shielded},
      writes: {PlayerShieldVisuals},
      after: [collectShieldPickups],
    );
}
