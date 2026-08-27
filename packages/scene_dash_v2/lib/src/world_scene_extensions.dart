import 'package:flutter_scene/physics.dart' show PhysicsWorld;
import 'package:flutter_scene/scene.dart' show Node, Scene;
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';

/// Scene helpers for [World].
extension WorldSceneSurface on World {
  /// The physics world, for overlap queries and raycasts. Available when
  /// the game booted with `physics:`.
  PhysicsWorld get physics => resources.get<PhysicsWorld>();

  /// Every `flutter_scene` component of type [T] attached to [root]'s subtree,
  /// paired with the node carrying it.
  ///
  /// Reads the scene graph, not the ECS: this finds what a `.fscene` authored
  /// whether or not anything spawned an entity for it. [root] defaults to the
  /// scene root, and each `loadScene` mounts its own wrapper node beneath it,
  /// so pass the loaded root to scope the walk to one level. Empty in a
  /// headless game, where there is no scene.
  ///
  /// Lazily evaluated, so breaking out of the loop stops the walk. Nodes in an
  /// unloaded lazy prefab subtree are not visited.
  Iterable<(Node, T)> sceneComponents<T>({Node? root}) {
    final from = root ?? resources.tryGet<Scene>()?.root;
    return from == null ? const Iterable.empty() : _walkComponents<T>(from);
  }
}

/// Depth-first, node before children. Mirrors `Node.meshNodes`.
Iterable<(Node, T)> _walkComponents<T>(Node node) sync* {
  for (final component in node.getComponents<T>()) {
    yield (node, component);
  }
  for (final child in node.children) {
    yield* _walkComponents<T>(child);
  }
}
