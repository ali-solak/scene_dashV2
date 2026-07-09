import '../entity/entity.dart';
import '../world/world.dart';

/// A typed group of components that can be inserted onto an entity in one step.
///
/// Game code does not implement this directly. The `@Bundle` generator emits a
/// `mixin _$YourBundle on YourBundle implements SceneDashBundle` that provides
/// [insertInto]; the user applies it with `class YourBundle with _$YourBundle`.
/// `Commands.spawn(bundle)` then inserts every component the bundle declares.
abstract interface class SceneDashBundle {
  /// Inserts all of this bundle's components onto [entity] in [world]. Called by
  /// the command buffer at a safe boundary, so it may register stores and mutate
  /// component storage directly.
  void insertInto(World world, Entity entity);
}
