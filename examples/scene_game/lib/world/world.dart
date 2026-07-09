import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../game/physics_layers.dart';
import 'data/config.dart';

part 'systems/systems.dart';

/// Installs world setup: lighting, post-processing, and the ramp — v1's
/// plugin body without the class.
void installWorldGeometry(GameBuilder game) {
  game.addSystem(Schedules.startup, setupWorld, reads: const {});
}
