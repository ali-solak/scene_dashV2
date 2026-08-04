import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../world/data/config.dart';

part 'data/resources.dart';
part 'systems/systems.dart';

/// Ambient drifting light motes, one PBR [Node] each.
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
