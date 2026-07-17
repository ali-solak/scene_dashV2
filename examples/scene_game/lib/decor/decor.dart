import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../world/data/config.dart';

part 'data/resources.dart';
part 'systems/systems.dart';

/// Ambient decoration: many drifting emissive light motes. Each is its own
/// PBR [Node] rather than one instanced draw — a PBR `InstancedMesh` drawn
/// through the lit/shadow/IBL passes device-loses the Impeller Vulkan
/// backend on Mali GPUs (Pixel 8), while individual PBR nodes (like the rest
/// of the scene) render fine. 48 small spheres is a cheap handful of draws.
void installDecor(GameBuilder game) {
  game.world.insert(MoteField());
  game
    ..addSystem(
      Schedules.startup,
      spawnMotes,
      reads: const {},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(Schedules.update, animateMotes, reads: const {});
}
