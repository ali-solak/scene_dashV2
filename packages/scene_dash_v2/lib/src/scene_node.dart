import 'package:flutter_scene/scene.dart' show Node;

/// An object component that binds an ECS entity to a `flutter_scene` [Node].
///
/// Transform synchronization writes the bound node's **local** transform;
/// `flutter_scene` then performs its own hierarchy/world-transform propagation.
///
/// Annotated `@ObjectComponent` so that game code which references it in
/// `@Bundle`/`@Query` is classified correctly by the generator. The integration
/// does not run code generation itself; it registers the store on demand.
final class SceneNode {
  /// The bound scene-graph node.
  final Node node;

  const SceneNode(this.node);

  /// The first component of type [T] attached to the bound [node], or `null`.
  ///
  /// Sugar for `node.getComponent<T>()`, so a system holding a `SceneNode`
  /// (often via `Single<SceneNode>`) can reach a native `flutter_scene`
  /// component — a physics body, character controller, collider — without the
  /// extra `.node` hop:
  ///
  /// ```dart
  /// final controller = player.value.component<RapierKinematicCharacterController>();
  /// if (controller == null) return;
  /// ```
  ///
  /// Returns `null` when no such component is attached.
  T? component<T>() => node.getComponent<T>();
}

/// Tag marking an entity whose node transform is owned by physics (or another
/// authority) rather than by [SceneTransform], so generic ECS transform
/// synchronization ([SyncSceneNodesAdapter]) must skip it.
///
/// The pinned `flutter_scene` (0.18.x) steps its `PhysicsWorld` on a fixed
/// timestep and writes dynamic-body node transforms itself, interpolating each
/// rendered frame between the previous and current step. The sync's exclusion
/// therefore *cooperates* with that interpolation instead of fighting it:
/// skipping these entities leaves the interpolated pose intact rather than
/// stamping a stale [SceneTransform] over it. A kinematic character controller
/// that writes its own node transform is the same case — tag it here, and read
/// its post-move node translation *back* into [SceneTransform] if gameplay
/// (hit detection, camera) needs to see the resolved position.
///
/// See "transform authority" in `docs/concept.md` §22: every bound node must
/// have exactly one transform source.
final class PhysicsDriven {
  const PhysicsDriven();
}

/// Integration-managed tag marking a [SceneNode] entity whose node is
/// currently parented in the active scene graph.
///
/// **This is integration state, not something game code authors.** The scene
/// driver adds it when a bound node is parented (whether the integration queued
/// the parent operation or game code already parented the node) and removes it
/// on unmount/despawn; bundles must never include it. Normal gameplay systems do
/// not need it either: the integration guarantees nodes are mounted after each
/// relevant command boundary, so a queried [SceneNode] reached from ordinary
/// frame systems is already in the scene.
///
/// Filter on `Mounted` only for an advanced system that intentionally targets
/// scene-mounted entities while running in an unusual lifecycle phase.
final class Mounted {
  const Mounted();
}
