import 'package:flutter_scene/physics.dart'
    show Collider, OverlapHit, PhysicsWorld;
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3;

import 'scene_node_index.dart';

/// Per-hit callback for the entity-carrying overlap queries. Return `true` to
/// keep receiving hits, `false` to stop early (a burst pellet that only wants
/// its first target, a cap on victims per swing).
typedef EntityOverlapCallback = bool Function(Entity entity, OverlapHit hit);

const int _allLayers = 0xFFFFFFFF;

/// Overlap queries that return ECS entities.
///
/// Unbound nodes are skipped.
/// Results are filtered by [Collider.collisionLayer].
extension EntityOverlapQueries on PhysicsWorld {
  /// [PhysicsWorld.overlapSphere] with each hit resolved to its ECS entity.
  int overlapSphereEntities(
    SceneNodeIndex index,
    Vector3 center,
    double radius,
    EntityOverlapCallback onHit, {
    int layerMask = _allLayers,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) {
    final hits = overlapSphere(
      center,
      radius,
      layerMask: layerMask,
      includeFixed: includeFixed,
      includeKinematic: includeKinematic,
      includeDynamic: includeDynamic,
      includeTriggers: includeTriggers,
    );
    return _deliverEntityHits(index, hits, layerMask, onHit);
  }

  /// [PhysicsWorld.overlapBox] with each hit resolved to its ECS entity.
  int overlapBoxEntities(
    SceneNodeIndex index,
    Vector3 center,
    Vector3 halfExtents,
    Quaternion rotation,
    EntityOverlapCallback onHit, {
    int layerMask = _allLayers,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  }) {
    final hits = overlapBox(
      center,
      halfExtents,
      rotation,
      layerMask: layerMask,
      includeFixed: includeFixed,
      includeKinematic: includeKinematic,
      includeDynamic: includeDynamic,
      includeTriggers: includeTriggers,
    );
    return _deliverEntityHits(index, hits, layerMask, onHit);
  }
}

int _deliverEntityHits(
  SceneNodeIndex index,
  List<OverlapHit> hits,
  int layerMask,
  EntityOverlapCallback onHit,
) {
  var delivered = 0;
  for (var i = 0; i < hits.length; i++) {
    final hit = hits[i];
    if (layerMask != _allLayers) {
      final collider = hit.collider;
      if (collider is! Collider || (collider.collisionLayer & layerMask) == 0) {
        continue;
      }
    }
    final entity = index.entityOf(hit.node);
    if (entity == null) continue;
    delivered++;
    if (!onHit(entity, hit)) break;
  }
  return delivered;
}
