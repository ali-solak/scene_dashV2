import '../entity/entity.dart';
import '../world/world.dart';

/// Inserts a group of components.
abstract interface class SceneDashBundle {
  /// Inserts all of this bundle's components onto [entity] in [world]. Called by
  /// the command buffer at a safe boundary, so it may register stores and mutate
  /// component storage directly.
  void insertInto(World world, Entity entity);
}
