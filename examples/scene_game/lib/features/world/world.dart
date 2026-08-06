import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../../common/bounds.dart';
import '../../common/physics_layers.dart';
import 'data/config.dart';
import 'package:flutter_scene/physics.dart';

part 'systems/systems.dart';

void installWorldGeometry(GameBuilder game) {
  game
    ..addSystem(
      Schedules.startup,
      setupWorld,
      reads: const {},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      despawnOutOfBounds,
      reads: {DespawnOutside, NodeRef},
    );
}
