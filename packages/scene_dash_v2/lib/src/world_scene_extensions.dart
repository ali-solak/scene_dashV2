import 'package:flutter_scene/physics.dart' show PhysicsWorld;
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';

import 'gizmos.dart';

/// Scene helpers for [World].
extension WorldSceneSurface on World {
  /// Debug shapes for the current frame.
  Gizmos get gizmos =>
      resources.getOrInsert<Gizmos>(() => Gizmos()..enabled = false);

  /// The physics world, for overlap queries and raycasts. Available when
  /// the game booted with `physics:`.
  PhysicsWorld get physics => resources.get<PhysicsWorld>();
}
