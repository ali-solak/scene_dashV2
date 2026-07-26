/// Shared out-of-bounds despawning. A bundle carries a [DespawnOutside]
/// part describing where its entity may be, and one generic system sweeps
/// every carrier — rocks, pickups and shots reuse it instead of
/// hand-rolling per-feature kill planes.
library;

import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

/// The region an entity may occupy, as optional per-axis kill planes.
/// Leaving it despawns the entity (deferred, so safe mid-query like every
/// structural verb).
final class DespawnOutside {
  const DespawnOutside({this.minY, this.minZ, this.maxZ});

  final double? minY;
  final double? minZ;
  final double? maxZ;

  bool contains(Vector3 position) {
    final minY = this.minY, minZ = this.minZ, maxZ = this.maxZ;
    if (minY != null && position.y < minY) return false;
    if (minZ != null && position.z < minZ) return false;
    if (maxZ != null && position.z > maxZ) return false;
    return true;
  }
}

// Reused scratch so the per-entity position read allocates nothing.
final Vector3 _positionScratch = Vector3.zero();

/// Despawns any [DespawnOutside] carrier whose node left its region — one
/// system serving every feature through a shared data component.
void despawnOutOfBounds(World world) {
  world.query2<DespawnOutside, SceneNode>().each((entity, bounds, binding) {
    binding.node.globalTranslationInto(_positionScratch);
    if (!bounds.contains(_positionScratch)) {
      world.despawn(entity);
    }
  });
}
