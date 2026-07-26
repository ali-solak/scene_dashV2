import 'package:flutter_scene/scene.dart' show Node;
import 'package:scene_dash_v2_core/advanced.dart';

/// Resolves scene nodes to entities.
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
