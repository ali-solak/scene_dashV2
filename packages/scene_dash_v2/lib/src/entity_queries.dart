import 'package:flutter_scene/scene.dart'
    show Collider, OverlapHit, PhysicsWorld;
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3;

import 'scene_node_index.dart';

/// Per-hit callback for the entity-carrying overlap queries. Return `true` to
/// keep receiving hits, `false` to stop early (a burst pellet that only wants
/// its first target, a cap on victims per swing).
typedef EntityOverlapCallback = bool Function(Entity entity, OverlapHit hit);

const int _allLayers = 0xFFFFFFFF;

/// Immediate overlap queries that deliver ECS entities instead of raw nodes.
///
/// A plain [PhysicsWorld.overlapSphere] returns node-level [OverlapHit]s, so
/// every gameplay consumer repeats the same resolution preamble: filter the
/// hit's collider by layer, call [SceneNodeIndex.entityOf], skip the misses.
/// These extensions do that once, the synchronous counterpart of what
/// [EntityCollisionPlugin] does for the async collision stream — hit
/// detection that runs *inside* a system (melee swings, projectile radii)
/// cannot wait a frame for an event, so it queries and resolves inline.
///
/// This is an extension, not a resource or plugin, on purpose: it is a pure
/// function of two resources systems already inject, so there is no lifecycle
/// to register and nothing new to wire —
///
/// ```dart
/// void run(
///   @Resource() PhysicsWorld physics,
///   @Resource() SceneNodeIndex index,
///   ...
/// ) {
///   physics.overlapSphereEntities(index, center, radius,
///       layerMask: Layers.enemy, includeTriggers: false, (entity, hit) {
///     // e.g. enemies.get(entity, (e, health, _) => health.damage(swing));
///     return true; // keep scanning; return false to stop early
///   });
/// }
/// ```
///
/// Semantics:
///
/// * **Only resolved hits are delivered.** A collider whose node (and
///   ancestors) is not entity-bound — static level geometry — is skipped.
///   Use the raw overlap query when unmanaged hits matter.
/// * **[layerMask] is enforced result-side too.** The mask is passed down to
///   the backend *and* re-checked against [Collider.collisionLayer] on each
///   hit, because some backends accept the parameter without forwarding it
///   to their native query (flutter_scene_rapier 0.2.x). The re-check is one
///   AND on backends that do forward. With a non-default mask, a hit whose
///   collider is not a [Collider] (layer unknowable) is excluded.
/// * **One delivery per matching collider,** so a node carrying several
///   colliders on the queried layer resolves to the same entity more than
///   once. Consumers that must act once per entity (damage) should dedup
///   across the attack anyway — a per-swing `Set<Entity>` — which subsumes
///   per-query dedup.
/// * The return value is the number of hits delivered to [onHit], counting
///   the one that stopped the scan.
///
/// The backend allocates the underlying hit list per query (upstream
/// behaviour); the wrapper itself adds only the callback closure at the call
/// site and iterates without further allocation.
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
