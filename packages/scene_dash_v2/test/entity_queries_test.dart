import 'dart:async';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3;

/// Fake world that returns canned overlap hits and records the arguments the
/// wrapper forwarded. Only the overlap queries are real.
final class _FakeWorld extends PhysicsWorld {
  List<OverlapHit> cannedHits = const [];
  int? lastLayerMask;
  bool? lastIncludeTriggers;
  Vector3? lastCenter;
  double? lastRadius;
  Vector3? lastHalfExtents;

  @override
  String get backendName => 'fake';

  @override
  Stream<CollisionEvent> get collisions => const Stream.empty();

  @override
  List<OverlapHit> overlapSphere(
    Vector3 center,
    double radius, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) {
    lastCenter = center;
    lastRadius = radius;
    lastLayerMask = layerMask;
    lastIncludeTriggers = includeTriggers;
    return cannedHits;
  }

  @override
  List<OverlapHit> overlapBox(
    Vector3 center,
    Vector3 halfExtents,
    Quaternion rotation, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) {
    lastCenter = center;
    lastHalfExtents = halfExtents;
    lastLayerMask = layerMask;
    lastIncludeTriggers = includeTriggers;
    return cannedHits;
  }

  @override
  void step(double fixedDt) {}

  @override
  void interpolateTransforms(double alpha) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Collider stub carrying only a layer; the rest is unimplemented on purpose
/// (the wrapper reads nothing else).
final class _LayerCollider extends Collider {
  _LayerCollider(this._layer);

  final int _layer;

  @override
  int get collisionLayer => _layer;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A collider component that is not a [Collider] — its layer is unknowable.
final class _OpaqueCollider extends Component {}

const int rockLayer = 1 << 2;
const int otherLayer = 1 << 3;

OverlapHit _hit(Node node, {Component? collider}) =>
    OverlapHit(node: node, collider: collider ?? _LayerCollider(rockLayer));

void main() {
  late _FakeWorld physics;
  late World world;

  setUp(() {
    physics = _FakeWorld();
    world = World();
  });

  (Entity, Node) spawnBound(Map<Node, Entity> bindings) {
    final entity = world.entities.spawn();
    final node = Node();
    bindings[node] = entity;
    return (entity, node);
  }

  test('delivers resolved entities and forwards the query arguments', () {
    final bindings = <Node, Entity>{};
    final (entity, node) = spawnBound(bindings);
    physics.cannedHits = [_hit(node)];

    final seen = <Entity>[];
    final center = Vector3(1, 2, 3);
    final count = physics.overlapSphereEntities(
      SceneNodeIndex(bindings),
      center,
      0.5,
      layerMask: rockLayer,
      includeTriggers: true,
      (hitEntity, hit) {
        seen.add(hitEntity);
        expect(hit.node, node);
        return true;
      },
    );

    expect(count, 1);
    expect(seen, [entity]);
    expect(physics.lastCenter, center);
    expect(physics.lastRadius, 0.5);
    expect(physics.lastLayerMask, rockLayer);
    expect(physics.lastIncludeTriggers, isTrue);
  });

  test('resolves a hit on a child mesh to the bound ancestor entity', () {
    final bindings = <Node, Entity>{};
    final (entity, node) = spawnBound(bindings);
    final childMesh = Node();
    node.add(childMesh);
    physics.cannedHits = [_hit(childMesh)];

    Entity? resolved;
    physics.overlapSphereEntities(
      SceneNodeIndex(bindings),
      Vector3.zero(),
      1,
      (hitEntity, hit) {
        resolved = hitEntity;
        return true;
      },
    );

    expect(resolved, entity);
  });

  test('skips hits whose node is not entity-bound', () {
    final bindings = <Node, Entity>{};
    final (entity, node) = spawnBound(bindings);
    physics.cannedHits = [_hit(Node()), _hit(node)]; // unmanaged, then bound

    final seen = <Entity>[];
    final count = physics.overlapSphereEntities(
      SceneNodeIndex(bindings),
      Vector3.zero(),
      1,
      (hitEntity, hit) {
        seen.add(hitEntity);
        return true;
      },
    );

    expect(count, 1);
    expect(seen, [entity]);
  });

  test('re-checks the layer result-side for backends that do not forward it',
      () {
    final bindings = <Node, Entity>{};
    final (entity, node) = spawnBound(bindings);
    final (_, wrongLayerNode) = spawnBound(bindings);
    final (_, opaqueNode) = spawnBound(bindings);
    // A backend that ignores layerMask returns all three.
    physics.cannedHits = [
      _hit(node, collider: _LayerCollider(rockLayer)),
      _hit(wrongLayerNode, collider: _LayerCollider(otherLayer)),
      _hit(opaqueNode, collider: _OpaqueCollider()),
    ];

    final seen = <Entity>[];
    physics.overlapSphereEntities(
      SceneNodeIndex(bindings),
      Vector3.zero(),
      1,
      layerMask: rockLayer,
      (hitEntity, hit) {
        seen.add(hitEntity);
        return true;
      },
    );

    expect(seen, [entity],
        reason: 'wrong-layer and unknowable colliders are excluded');
  });

  test('the default all-layers mask delivers every resolved hit', () {
    final bindings = <Node, Entity>{};
    final (a, nodeA) = spawnBound(bindings);
    final (b, nodeB) = spawnBound(bindings);
    physics.cannedHits = [
      _hit(nodeA, collider: _OpaqueCollider()), // layer unknowable is fine
      _hit(nodeB, collider: _LayerCollider(otherLayer)),
    ];

    final seen = <Entity>[];
    physics.overlapSphereEntities(
      SceneNodeIndex(bindings),
      Vector3.zero(),
      1,
      (hitEntity, hit) {
        seen.add(hitEntity);
        return true;
      },
    );

    expect(seen, [a, b]);
  });

  test('returning false stops the scan; the count includes that delivery', () {
    final bindings = <Node, Entity>{};
    final (a, nodeA) = spawnBound(bindings);
    final (_, nodeB) = spawnBound(bindings);
    physics.cannedHits = [_hit(nodeA), _hit(nodeB)];

    final seen = <Entity>[];
    final count = physics.overlapSphereEntities(
      SceneNodeIndex(bindings),
      Vector3.zero(),
      1,
      (hitEntity, hit) {
        seen.add(hitEntity);
        return false; // first target only
      },
    );

    expect(seen, [a]);
    expect(count, 1);
  });

  test('a multi-collider node delivers once per matching collider', () {
    final bindings = <Node, Entity>{};
    final (entity, node) = spawnBound(bindings);
    physics.cannedHits = [_hit(node), _hit(node)];

    final seen = <Entity>[];
    physics.overlapSphereEntities(
      SceneNodeIndex(bindings),
      Vector3.zero(),
      1,
      (hitEntity, hit) {
        seen.add(hitEntity);
        return true;
      },
    );

    expect(seen, [entity, entity],
        reason: 'per-entity dedup is the consumer\'s job (per-swing sets)');
  });

  test('overlapBoxEntities resolves and filters the same way', () {
    final bindings = <Node, Entity>{};
    final (entity, node) = spawnBound(bindings);
    final (_, wrongLayerNode) = spawnBound(bindings);
    physics.cannedHits = [
      _hit(node),
      _hit(wrongLayerNode, collider: _LayerCollider(otherLayer)),
      _hit(Node()), // unmanaged
    ];

    final seen = <Entity>[];
    final halfExtents = Vector3(1, 2, 3);
    final count = physics.overlapBoxEntities(
      SceneNodeIndex(bindings),
      Vector3.zero(),
      halfExtents,
      Quaternion.identity(),
      layerMask: rockLayer,
      (hitEntity, hit) {
        seen.add(hitEntity);
        return true;
      },
    );

    expect(count, 1);
    expect(seen, [entity]);
    expect(physics.lastHalfExtents, halfExtents);
    expect(physics.lastLayerMask, rockLayer);
  });
}
