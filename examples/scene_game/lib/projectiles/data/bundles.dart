part of '../projectiles.dart';

// Geometry and materials are shared across spawns; charged strength is shown
// with transform scale on the visual child, not a per-shot material.
final Material _projectileMaterial = PhysicallyBasedMaterial()
  ..baseColorFactor = Vector4(0.5, 0.9, 1.0, 1)
  ..emissiveFactor = Vector4(0.3, 0.85, 1.0, 1)
  ..metallicFactor = 0.08
  ..roughnessFactor = 0.18;
final Material _projectileGlowMaterial = glowMaterial(
  Vector4(0.38, 0.9, 1.0, 0.42),
  alpha: 0.42,
);
final Material _projectileTrailMaterial = glowMaterial(
  Vector4(0.18, 0.55, 1.0, 0.2),
  alpha: 0.2,
);

final Material _chargedMaterial = PhysicallyBasedMaterial()
  ..baseColorFactor = Vector4(0.86, 0.72, 1.0, 1)
  ..emissiveFactor = Vector4(0.72, 0.42, 1.15, 1)
  ..metallicFactor = 0.1
  ..roughnessFactor = 0.16;
final Material _chargedGlowMaterial = glowMaterial(
  Vector4(0.8, 0.55, 1.0, 0.5),
  alpha: 0.5,
);
final Material _chargedTrailMaterial = glowMaterial(
  Vector4(0.82, 0.46, 1.0, 0.34),
  alpha: 0.34,
);

final _projectileGeometry = SphereGeometry(radius: projectileRadius);
final _projectileGlowGeometry =
    SphereGeometry(radius: projectileRadius * 1.35);
final _projectileTrailGeometry = CuboidGeometry(Vector3(0.07, 0.07, 0.78));

/// A shot's spawn list: a fast trigger sphere with glow and trail children.
///
/// Scoped to the run: exiting `playing` despawns shots in flight. Max flight
/// time is the `DespawnAfter` part — the built-in ticker despawns the shot
/// when it elapses, so the update system only handles hits and
/// out-of-bounds.
List<Object> projectileBundle({required Vector3 position, double charge = 0}) {
  return [
    Projectile(charge: charge),
    SceneNode(_makeProjectileNode(position, charge)),
    const PhysicsDriven(),
    const DespawnOnExit(GameStatus.playing),
    DespawnAfter(projectileLifetime),
  ];
}

Node _makeProjectileNode(Vector3 position, double charge) {
  final scale = charge > 0 ? chargedProjectileScale(charge) : 1.0;
  final mainMaterial = charge > 0 ? _chargedMaterial : _projectileMaterial;
  final glowMat = charge > 0 ? _chargedGlowMaterial : _projectileGlowMaterial;
  final trailMat =
      charge > 0 ? _chargedTrailMaterial : _projectileTrailMaterial;
  final colliderRadius = projectileRadius * scale;
  final trailThickness = charge > 0 ? scale * 1.8 : 1.0;
  final trailLength = charge > 0 ? scale * 2.4 : 1.0;
  final trailOffsetZ = charge > 0 ? 0.38 * trailLength : 0.38;

  // The Rapier sync rewrites the root's local transform every frame (which
  // would erase a root scale), so the charged size lives on this child.
  final visual =
      Node(
          mesh: Mesh(_projectileGeometry, mainMaterial),
          localTransform: Matrix4.identity()
            ..scaleByDouble(scale, scale, scale, 1),
        )
        ..frustumCulled = false
        ..add(
          Node(mesh: Mesh(_projectileGlowGeometry, glowMat))
            ..frustumCulled = false,
        )
        ..add(
          Node(
            mesh: Mesh(_projectileTrailGeometry, trailMat),
            localTransform: Matrix4.translation(Vector3(0, 0, trailOffsetZ))
              ..scaleByDouble(trailThickness, trailThickness, trailLength, 1),
          )..frustumCulled = false,
        );

  return Node(localTransform: Matrix4.translation(position))
    ..frustumCulled = false
    ..add(visual)
    ..addComponent(
      RapierRigidBody(
        type: BodyType.dynamic_,
        mass: 0.04,
        ccdEnabled: true,
        linearVelocity: Vector3(0, projectileLaunchUp, -projectileSpeed),
        linearDamping: 0,
      ),
    )
    ..addComponent(
      RapierCollider(
        shape: SphereShape(radius: colliderRadius),
        isTrigger: true,
      ),
    );
}
