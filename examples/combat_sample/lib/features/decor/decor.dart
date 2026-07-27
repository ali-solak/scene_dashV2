import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

import '../world/data/config.dart' show windDirection;
import '../../fx/particles.dart' as fx;
import 'vfx/leaf_texture.dart';

part 'data/resources.dart';
part 'systems/systems.dart';

/// Ambient decoration: leaves turning down through the clearing.
///
/// One instanced emitter, one draw per card shape, and the engine owns the
/// fall. Their ambient drift stays independent from the state of the fight.
void installDecor(GameBuilder game) {
  game
    ..world.insert(LeafField())
    ..addSystem(
      Schedules.startup,
      spawnLeaves,
      reads: const {},
      runIf: hasResource<Scene>(),
    );
}
