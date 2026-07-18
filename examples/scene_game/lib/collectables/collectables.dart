import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../fx/anim.dart';
import '../fx/particles.dart' as fx;
import '../fx/particle_texture.dart';
import '../game/bounds.dart';
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

/// Installs rolling shield pickups, the player's [Shielded] condition, and
/// the shield feedback and deflection VFX. The shield has no resource and
/// no tick system: pickup adds `Shielded` with `removeAfter:`, the
/// framework expires it, and the HUD reads the deadline back through the
/// world.
void installCollectables(GameBuilder game) {
  game.world.insert(PickupLanes());
  game
    ..registerTag<Collectable>()
    ..registerTag<ShieldPickup>()
    ..registerComponent<Shielded>()
    // The bubble and badge follow the component's lifecycle — every
    // removal path (expiry, run reset, a future dispel) hides the bubble.
    ..observe<Shielded>(onAdd: shieldGained, onRemove: shieldLost)
    ..addSystem(
      OnEnter(GameStatus.playing),
      resetCollectablesOnRunStart,
      writes: {Shielded},
    )
    // fixedUpdate so the body is mounted before the native step. The
    // spawn itself is deferred to the command boundary, so the declared
    // writes are the feature-owned types, not the stores the bundle
    // lands in later. The cadence lives at registration: `.and` short-
    // circuits, so the period elapses only while playing (it carries any
    // leftover progress across runs, unlike the old per-run spawner
    // entity — acceptable for a pickup). Scene-gated like spawnPlayer:
    // the bundle builds GPU meshes, so headless boots skip the system.
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
      reads: {SceneNode},
      writes: {Shielded},
      inSet: GameSets.logic,
      runIf: inState(GameStatus.playing),
    )
    // After collection so a fresh pickup's deadline is already tracked
    // when the warning flash reads it.
    ..addSystem(
      Schedules.update,
      updateShieldVisuals,
      reads: {Shielded},
      writes: {PlayerShieldVisuals},
      after: [collectShieldPickups],
    );
  // Off-ramp cleanup is the bundle's DespawnOutside part (world feature).
}
