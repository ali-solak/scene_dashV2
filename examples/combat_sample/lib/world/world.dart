import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Quaternion, Vector3, Vector4;

import '../game/physics_layers.dart';
import 'data/assets.dart';
import 'data/components.dart';
import 'data/config.dart';
import 'data/layout.dart';
import 'data/resources.dart';
import 'vfx/forest.dart';
import 'vfx/grass_field.dart';

part 'systems/systems.dart';

/// Installs the stage: scene look (sky/sun/fog/rays), the clearing (ground +
/// collider, forest ring, grass field), and the wind that keeps the grass
/// moving. [assets] is loaded in `main` (imports are async); headless games
/// pass [WorldAssets.none] and the scene-gated systems never run.
Feature installWorld(WorldAssets assets) => (game) {
  game
    ..registerTag<Grass>()
    ..registerTag<Ocean>()
    ..world.insert(assets)
    ..world.insert(GrassWind())
    ..world.insert(WindState())
    ..addSystem(
      Schedules.startup,
      setupWorld,
      reads: const {},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.startup,
      spawnClearing,
      writes: const {Grass, Ocean},
      after: const [setupWorld],
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateWindMaterials,
      reads: const {Grass, Ocean, SceneNode},
      runIf: hasResource<Scene>(),
    );
};
