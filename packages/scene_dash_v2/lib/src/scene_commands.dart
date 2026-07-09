import 'package:flutter_scene/scene.dart' show Component, Node;

/// A buffer of deferred scene-graph mutations.
///
/// ECS systems should not mutate the `flutter_scene` graph mid-frame. They
/// record operations here; the integration flushes them at a safe scene boundary via
/// [flush]. Constructed with the default parent [Node] (normally `scene.root`).
final class SceneCommands {
  final Node _root;
  final List<void Function()> _queue = <void Function()>[];

  SceneCommands(this._root);

  /// Whether there are no pending operations.
  bool get isEmpty => _queue.isEmpty;

  /// Queues adding [node] under [parent] (defaults to the root node).
  void add(Node node, {Node? parent}) {
    _queue.add(() => (parent ?? _root).add(node));
  }

  /// Queues removing [node] from its current parent.
  void remove(Node node) {
    _queue.add(() => node.parent?.remove(node));
  }

  /// Queues attaching [component] to [node].
  void attach(Node node, Component component) {
    _queue.add(() => node.addComponent(component));
  }

  /// Queues detaching [component] from [node].
  void detach(Node node, Component component) {
    _queue.add(() => node.removeComponent(component));
  }

  /// Applies and clears all queued operations.
  void flush() {
    if (_queue.isEmpty) return;
    for (var i = 0; i < _queue.length; i++) {
      _queue[i]();
    }
    _queue.clear();
  }
}
