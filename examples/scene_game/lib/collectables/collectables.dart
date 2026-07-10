import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../fx/anim.dart';
import '../fx/instanced_pool.dart';
import '../game/game_state.dart';
import '../game/physics_layers.dart';
import '../game/sets.dart';
import '../player/data/config.dart';
import '../player/player.dart';
import 'data/config.dart';

part 'data/components.dart';
part 'data/resources.dart';
part 'data/bundles.dart';
part 'vfx/vfx.dart';
part 'systems/systems.dart';

/// Installs rolling shield pickups, the shield state, and the player's
/// shield feedback and deflection VFX. The feature owns and inserts the
/// [ShieldState]; the HUD reads it back through the world.
void installCollectables(GameBuilder game) {
  game.world
    ..insert(ShieldState())
    ..insert(CollectableSpawner())
    ..insert(ShieldDeflectVfx());
  game
    ..registerTag<Collectable>()
    ..registerTag<ShieldPickup>()
    ..addSystem(
      OnEnter(GameStatus.playing),
      resetCollectablesOnRunStart,
      reads: const {},
    )
    // fixedUpdate so the body is mounted before the native step. The
    // spawn itself is deferred to the command boundary, so the declared
    // writes are the feature-owned types, not the stores the bundle
    // lands in later.
    ..addSystem(
      Schedules.fixedUpdate,
      spawnShieldPickups,
      writes: {Collectable, ShieldPickup},
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(
      Schedules.startup,
      spawnShieldDeflectVfx,
      reads: const {},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateShieldState,
      reads: const {},
      inSet: GameSets.logic,
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(
      Schedules.update,
      animateShieldPickups,
      writes: {ShieldPickupState, ShieldPickupVisuals},
    )
    // After the shield tick so a fresh shield isn't ticked down this
    // frame.
    ..addSystem(
      Schedules.update,
      collectShieldPickups,
      reads: {SceneNode},
      inSet: GameSets.logic,
      after: [updateShieldState],
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(
      Schedules.update,
      updateShieldVisuals,
      writes: {PlayerShieldVisuals},
      after: [updateShieldState],
    )
    ..addSystem(Schedules.update, cleanupPickups, reads: {SceneNode})
    ..addSystem(Schedules.update, updateShieldDeflectVfx, reads: const {});
}
