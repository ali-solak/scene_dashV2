import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Vector4;

import '../game/sets.dart';
import '../world/data/config.dart' show windDirection;
import '../world/data/resources.dart' show WindState;
import 'vfx/leaf_texture.dart';

part 'data/resources.dart';
part 'systems/systems.dart';

/// Ambient decoration: leaves turning down through the clearing.
///
/// Each leaf is its own [Node] sharing one quad and a few materials; a
/// translucent `InstancedMesh` buys nothing here and a per-leaf draw of
/// one two-triangle quad is cheap. They ride the fight's own [WindState]
/// rather than a private clock, so the leaves gust when the pack circles
/// and settle while a barbarian telegraphs.
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
