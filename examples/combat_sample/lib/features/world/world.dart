import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../../fx/wave_crash.dart';
import '../../common/physics_layers.dart';
import 'data/assets.dart';
import 'data/components.dart';
import 'data/config.dart';
import 'data/layout.dart';
import 'data/resources.dart';
import 'vfx/forest.dart';
import 'vfx/grass_field.dart';
import 'package:flutter_scene/physics.dart';

part 'systems/stage.dart';
part 'systems/clearing.dart';
part 'systems/weather.dart';

/// Installs the stage as three sub-features: the scene look, the
/// clearing's geometry, and the weather that keeps it moving. [assets]
/// is loaded in `main` (imports are async); headless games pass
/// [WorldAssets.none] and the scene-gated systems never run.
Feature installWorld(WorldAssets assets) => (game) {
  game.world.insert(assets);
  installStageLook(game);
  installClearing(game);
  installWeather(game);
};
