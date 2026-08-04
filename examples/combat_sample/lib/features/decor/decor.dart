import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector4;

import '../../common/sets.dart';
import '../world/data/config.dart' show windDirection;
import 'vfx/leaf_texture.dart';

part 'data/resources.dart';
part 'systems/systems.dart';

/// Ambient decoration: leaves turning down through the clearing.
///
/// One [Node] per leaf, sharing a quad. Tried as a
/// `MeshParticleEmitterComponent` and reverted: web went 100+ fps to 30 at
/// every quality level, because the per-particle `Matrix4` and
/// `Quaternion` cost more than the draws instancing saves.
void installDecor(GameBuilder game) {
  game
    ..world.insert(LeafField())
    ..addSystem(
      Schedules.startup,
      spawnLeaves,
      reads: const {},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      animateLeaves,
      inSet: GameSets.logic,
      reads: const {},
      runIf: hasResource<Scene>(),
    );
}
