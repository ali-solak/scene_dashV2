import 'package:flutter_scene/scene.dart' show Node;
import 'package:scene_dash_v2_core/advanced.dart';

import 'scene_commands.dart';
import 'node_ref.dart';

/// Mounts entity nodes and removes unused mounts.
final class SceneNodeMountAdapter
    implements SystemAdapter, SystemAccessProvider, StoreChangeListener {
  @override
  SystemAccess get access =>
      const SystemAccess(reads: <Type>{NodeRef}, writes: <Type>{Mounted});

  final SceneCommands _sceneCommands;

  /// Live node to entity index.
  final Map<Node, Entity> _index;

  late final World _world;
  late final ObjectComponentStore<NodeRef> _nodeRefs;
  late final TagStore _mounted;

  /// Nodes this adapter mounted, mapped to the entity they were mounted for.
  final Map<Node, Entity> _ownedMounted = <Node, Entity>{};

  /// Every bound node, mapped to the entity that bound it last.
  final Map<Node, Entity> _knownBound = <Node, Entity>{};

  final Map<int, Node> _nodeByEntityIndex = <int, Node>{};
  final Map<Node, List<int>> _binders = <Node, List<int>>{};
  final Set<int> _dirty = <int>{};
  final List<Node> _unbound = <Node>[];
  bool _cleared = false;

  SceneNodeMountAdapter(this._sceneCommands, this._index);

  @override
  void initialize(World world) {
    _world = world;
    _nodeRefs = world.ensureObjectStore<NodeRef>()..addChangeListener(this);
    _mounted = world.ensureTagStore<Mounted>();
    for (var dense = 0; dense < _nodeRefs.length; dense++) {
      _dirty.add(_nodeRefs.entityIndexAt(dense));
    }
  }

  @override
  void rowChanged(int entityIndex) => _dirty.add(entityIndex);

  @override
  void cleared() => _cleared = true;

  @override
  void run() {
    if (_cleared) _forgetAll();
    if (_dirty.isEmpty && _unbound.isEmpty) return;
    for (final entityIndex in _dirty) {
      _reconcile(entityIndex);
    }
    _dirty.clear();
    for (final node in _unbound) {
      _settle(node);
    }
    _unbound.clear();
  }

  void _forgetAll() {
    _cleared = false;
    _unbound.addAll(_nodeByEntityIndex.values);
    _nodeByEntityIndex.clear();
    for (final binders in _binders.values) {
      binders.clear();
    }
  }

  void _reconcile(int entityIndex) {
    final node = _nodeRefs.valueOf(entityIndex)?.node;
    final previous = _nodeByEntityIndex[entityIndex];
    if (previous != null && !identical(previous, node)) {
      _nodeByEntityIndex.remove(entityIndex);
      _binders[previous]?.remove(entityIndex);
      _unbound.add(previous);
      if (node == null) _mounted.removeEntityIndex(entityIndex);
    }
    if (node == null) return;
    _nodeByEntityIndex[entityIndex] = node;
    final binders = _binders.putIfAbsent(node, () => <int>[]);
    if (!binders.contains(entityIndex)) binders.add(entityIndex);
    _bind(node, _world.entities.resolve(entityIndex));
  }

  void _bind(Node node, Entity entity) {
    final previousEntity = _knownBound[node];
    if (previousEntity != null &&
        previousEntity != entity &&
        _world.isAlive(previousEntity) &&
        !_nodeByEntityIndex.containsKey(previousEntity.index)) {
      _mounted.removeEntityIndex(previousEntity.index);
    }
    _knownBound[node] = entity;
    _index[node] = entity;
    if (_ownedMounted.containsKey(node)) {
      _ownedMounted[node] = entity;
    } else if (node.parent == null) {
      _sceneCommands.add(node);
      _ownedMounted[node] = entity;
    }
    _mounted.add(entity.index);
  }

  void _settle(Node node) {
    final binders = _binders[node];
    if (binders == null || binders.isEmpty) {
      _binders.remove(node);
      _release(node);
      return;
    }
    final owner = _knownBound[node];
    if (owner != null &&
        _world.isAlive(owner) &&
        binders.contains(owner.index)) {
      return;
    }
    _bind(node, _world.entities.resolve(binders.last));
  }

  void _release(Node node) {
    _knownBound.remove(node);
    _index.remove(node);
    if (_ownedMounted.remove(node) != null) _sceneCommands.remove(node);
  }
}
