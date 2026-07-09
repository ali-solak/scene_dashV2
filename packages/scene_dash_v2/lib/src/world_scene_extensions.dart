import 'package:flutter_scene/scene.dart' show PhysicsWorld;
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';

import 'gizmos.dart';

/// The integration members of the world surface (D8): promoted getters for
/// the scene-side plumbing, so `resource<T>()` stays reserved for the
/// game's own singletons.
extension WorldSceneSurface on World {
  /// Immediate-mode debug shapes for the current frame. The render layer
  /// is opt-in — add `installGizmos(...)` to the feature list to draw.
  /// Without it this is a disabled recorder, so submission calls in
  /// shipping code stay safe no-ops everywhere (headless included).
  Gizmos get gizmos =>
      resources.getOrInsert<Gizmos>(() => Gizmos()..enabled = false);

  /// The physics world, for overlap queries and raycasts. Available when
  /// the game booted with `physics:`.
  PhysicsWorld get physics => resources.get<PhysicsWorld>();
}
