import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector4;

import '../fx/instanced_pool.dart';
import '../world/data/config.dart';

part 'data/resources.dart';
part 'systems/systems.dart';

/// Ambient decoration: many drifting light motes drawn as one
/// [InstancedPool] (one node, one draw call) instead of one entity/node per
/// mote — the data-oriented rendering path for homogeneous visuals.
void installDecor(GameBuilder game) {
  game.world.insert(MoteField());
  game
    ..addSystem(Schedules.startup, spawnMotes, reads: const {})
    ..addSystem(Schedules.update, animateMotes, reads: const {});
}
