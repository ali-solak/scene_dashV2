library;

import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

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

// Shared scratch avoids frame allocations.
final Vector3 _positionScratch = Vector3.zero();

void despawnOutOfBounds(World world) {
  world.query2<DespawnOutside, NodeRef>().each((entity, bounds, binding) {
    binding.node.globalTranslationInto(_positionScratch);
    if (!bounds.contains(_positionScratch)) {
      world.despawn(entity);
    }
  });
}
