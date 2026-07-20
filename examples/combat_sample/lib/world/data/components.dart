/// World-feature components.
library;

import 'package:scene_dash_v2/scene_dash_v2.dart' show Tag;

/// Tags the grass-field entity, so the wind system reaches its material
/// through the ECS (`query<SceneNode>(require: [Grass])`) instead of a
/// shared mutable resource.
final class Grass implements Tag {
  const Grass();
}

/// Tags the ocean entity below the cliff; the same wind clock drives its
/// wave `time` parameter.
final class Ocean implements Tag {
  const Ocean();
}
