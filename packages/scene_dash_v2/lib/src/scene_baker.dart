import 'package:flutter_scene/scene.dart' show Node, Scene;
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';

import 'node_ref.dart';
import 'world_scene_extensions.dart';

/// Builds the spawn list for one authored node.
typedef SceneBundle<T> = List<Object> Function(Node node, T component);

/// Which nodes each baked type has already spawned an entity for.
///
/// Holds the nodes strongly, so a level that is unloaded and will not be baked
/// again should be dropped with [forget].
final class SceneBakeLog {
  final Map<Type, Set<Node>> _baked = <Type, Set<Node>>{};

  /// Records [node] as baked for [type]; false when it already was.
  bool mark(Type type, Node node) =>
      (_baked[type] ??= <Node>{}).add(node);

  /// Nodes baked for [type] so far.
  int countFor(Type type) => _baked[type]?.length ?? 0;

  /// Drops the record for [type], so its nodes bake again.
  void forget(Type type) => _baked.remove(type);
}

/// Spawning scene-authored components as entities.
extension WorldSceneBaking on World {
  /// Spawns one entity per [T] found in the scene, skipping nodes already
  /// baked for [T].
  ///
  /// Call after mounting a scene loaded later than boot; [installSceneBaker]
  /// does the first pass at startup. Idempotent, so re-running after adding a
  /// level only bakes the new nodes. Returns how many entities were spawned.
  ///
  /// [bundle] builds each entity's components, defaulting to the authored
  /// component plus a [NodeRef]. Types it returns must be registered
  /// (`registerComponent`/`registerTag` at install time) or they park unseen.
  int bakeSceneComponents<T extends Object>({
    SceneBundle<T>? bundle,
    Node? root,
  }) {
    final log = resources.getOrInsert<SceneBakeLog>(SceneBakeLog.new);
    var spawned = 0;
    for (final (node, component) in sceneComponents<T>(root: root)) {
      if (!log.mark(T, node)) continue;
      spawn(
        bundle?.call(node, component) ?? <Object>[component, NodeRef(node)],
      );
      spawned++;
    }
    return spawned;
  }
}

/// Installs a startup pass that turns every scene-authored [T] into an entity.
///
/// The authored component is attached to a node by `flutter_scene` when the
/// document loads; this bridges it into the ECS so systems can query it.
///
/// ```dart
/// features: [
///   installSceneBaker<Torch>(),
///   installSceneBaker<SpawnPoint>(
///     bundle: (node, spawn) => [spawn, NodeRef(node), Patrol()],
///   ),
/// ]
/// ```
///
/// Sharing the authored instance is right for immutable placement data; put
/// mutable runtime state in its own component through [bundle] so gameplay
/// never writes back into what the document authored.
///
/// Only sees nodes reachable from the scene when `Schedules.startup` runs —
/// nodes queued through `SceneCommands` are still unflushed at that point. Use
/// [WorldSceneBaking.bakeSceneComponents] for anything mounted later.
Feature installSceneBaker<T extends Object>({
  SceneBundle<T>? bundle,
  Node? root,
  Set<Type> writes = const <Type>{},
}) {
  return (game) {
    game
      ..registerComponent<T>()
      ..registerComponent<NodeRef>()
      ..addSystem(
        Schedules.startup,
        (world) => world.bakeSceneComponents<T>(bundle: bundle, root: root),
        writes: <Type>{T, NodeRef, ...writes},
        runIf: hasResource<Scene>(),
        // Generated closures otherwise all label as `closure`.
        label: 'sceneBaker<$T>',
      );
  };
}
