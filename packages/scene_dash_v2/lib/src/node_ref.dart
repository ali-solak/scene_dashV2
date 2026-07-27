import 'package:flutter_scene/scene.dart' show Node;

/// An object component that binds an ECS entity to a `flutter_scene` [Node].
final class NodeRef {
  /// The bound scene-graph node.
  final Node node;

  const NodeRef(this.node);

  /// The first [T] attached to [node].
  T? component<T>() => node.getComponent<T>();
}

/// Marks a node transform as externally controlled.
final class PhysicsDriven {
  const PhysicsDriven();
}

/// Marks a node as mounted in the active scene.
final class Mounted {
  const Mounted();
}
