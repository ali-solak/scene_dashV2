import 'package:flutter_scene/physics.dart' show PhysicsWorld;
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';

import 'debug_draw.dart';

/// Scene helpers for [World].
extension WorldSceneSurface on World {
  /// Debug shapes for the current frame.
  DebugDraw get debugDraw =>
      resources.getOrInsert<DebugDraw>(() => DebugDraw()..enabled = false);

  /// The physics world, for overlap queries and raycasts. Available when
  /// the game booted with `physics:`.
  PhysicsWorld get physics => resources.get<PhysicsWorld>();
}
