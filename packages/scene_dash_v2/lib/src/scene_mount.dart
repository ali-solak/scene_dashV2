import 'package:flutter_scene/scene.dart' show Node;
import 'package:scene_dash_v2_core/advanced.dart';

import 'scene_commands.dart';
import 'node_ref.dart';

/// Mounts entity nodes and removes unused mounts.
final class SceneNodeMountAdapter
    implements SystemAdapter, SystemAccessProvider {
  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{NodeRef}, writes: <Type>{Mounted});

  final SceneCommands _sceneCommands;

  /// Live node to entity index.
  final Map<Node, Entity> _index;

  late final World _world;
  late final ObjectComponentStore<NodeRef> _sceneNodeStore;
  late final Query1<NodeRef> _bound;

  /// Nodes this adapter mounted, mapped to the entity they were mounted for.
  final Map<Node, Entity> _ownedMounted = <Node, Entity>{};

  /// Every bound node seen during the last reconciliation pass.
  final Map<Node, Entity> _knownBound = <Node, Entity>{};

  /// Nodes seen this run.
  final Set<Node> _seen = <Node>{};

  /// Scratch lists of entities to (un)tag, applied after the bound query stops
  /// iterating (tag stores cannot be mutated mid-query). Reused each run.
  final List<Entity> _toTag = <Entity>[];
  final List<Entity> _toUntag = <Entity>[];

  int _lastRevision = -1;

  SceneNodeMountAdapter(this._sceneCommands, this._index);

  @override
  void initialize(World world) {
    _world = world;
    world
      ..ensureObjectStore<NodeRef>()
      ..ensureTagStore<Mounted>();
    _sceneNodeStore = world.stores.object<NodeRef>();
    _bound = world.query1<NodeRef>();
  }

  @override
  void run() {
    final revision = _sceneNodeStore.revision;
    if (revision == _lastRevision) return;
    _lastRevision = revision;

    _seen.clear();
    _toTag.clear();
    _toUntag.clear();
    _bound.each((entity, binding) {
      final node = binding.node;
      _seen.add(node);
      final previousEntity = _knownBound[node];
      if (previousEntity != null && previousEntity != entity) {
        _toUntag.add(previousEntity);
      }
      _knownBound[node] = entity;
      // Maintain the reverse node -> entity index for every bound node (not just
      // ones we mount), so picking can resolve any visible node to its entity.
      _index[node] = entity;
      if (_ownedMounted.containsKey(node)) {
        _ownedMounted[node] = entity;
        _toTag.add(entity);
        return;
      }
      // Adopt only nodes that have no parent yet; a node the game parented
      // itself is left alone (and never tracked for auto-detach).
      if (node.parent == null) {
        _sceneCommands.add(node);
        _ownedMounted[node] = entity;
        _toTag.add(entity);
      } else {
        _toTag.add(entity);
      }
    });
    // Forget nodes whose binding disappeared. Only detach nodes this adapter
    // adopted; game-parented nodes are untagged/index-pruned but left in place.
    _knownBound.removeWhere((node, entity) {
      if (_seen.contains(node)) return false;
      _toUntag.add(entity);
      if (_ownedMounted.remove(node) != null) {
        _sceneCommands.remove(node);
      }
      return true;
    });
    // Prune index entries whose node is no longer bound (despawn, component
    // removal, or replacement). Reuses the scan's _seen set, no allocation.
    _index.removeWhere((node, _) => !_seen.contains(node));

    // Apply mount tags after the query.
    final mounted = _world.ensureTagStore<Mounted>();
    for (final entity in _toUntag) {
      if (_world.isAlive(entity)) mounted.removeEntityIndex(entity.index);
    }
    for (final entity in _toTag) {
      if (_world.isAlive(entity)) mounted.add(entity.index);
    }
  }
}
