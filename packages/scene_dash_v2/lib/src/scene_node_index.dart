import 'package:flutter_scene/scene.dart' show Node;
import 'package:scene_dash_v2_core/advanced.dart';

/// Reverse lookup from a scene [Node] back to the ECS [Entity] that owns it
/// through its `SceneNode`. Injected into systems as an `@Resource()`.
///
/// `SceneNode` is entity → node; this is the other direction, which you need
/// to turn a visual hit back into gameplay. A `Scene.raycast` or `ScenePointer`
/// hit returns a [Node]; pass it to [entityOf] to get the entity to act on.
/// [entityOf] walks up ancestors, so a hit on a nested child mesh still resolves
/// to the bound entity.
///
/// The integration maintains it each frame in the mount step (before the
/// `update` phase), piggybacking on the scan it already does over bound nodes —
/// no extra per-frame allocation. It therefore reflects the entities bound as of
/// this frame's mount step.
final class SceneNodeIndex {
  /// Created by the integration; [byNode] is the live map it maintains.
  SceneNodeIndex(this._byNode);

  final Map<Node, Entity> _byNode;

  /// The entity bound to [node] or its nearest indexed ancestor, or `null` when
  /// no ancestor is a bound `SceneNode` node.
  Entity? entityOf(Node node) {
    Node? current = node;
    while (current != null) {
      final entity = _byNode[current];
      if (entity != null) return entity;
      current = current.parent;
    }
    return null;
  }

  /// Number of bound nodes currently indexed.
  int get length => _byNode.length;
}
