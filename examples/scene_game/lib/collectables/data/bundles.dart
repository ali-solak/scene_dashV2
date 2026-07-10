part of '../collectables.dart';

final Material _pickupMaterial = PhysicallyBasedMaterial()
  ..baseColorFactor = Vector4(0.25, 0.7, 1.0, 1)
  ..metallicFactor = 0.32
  ..roughnessFactor = 0.22
  ..emissiveFactor = Vector4(0.1, 0.45, 0.8, 1);
final Material _glowMaterial = PhysicallyBasedMaterial()
  ..baseColorFactor = Vector4(0.4, 0.85, 1.0, 0.32)
  ..emissiveFactor = Vector4(0.5, 1.1, 1.5, 1)
  ..metallicFactor = 0
  ..roughnessFactor = 0.2
  ..alphaMode = AlphaMode.blend;

final _pickupGeometry = SphereGeometry(radius: collectableRadius);
final _glowGeometry = SphereGeometry(radius: collectableRadius * 1.5);

/// A rolling shield pickup's spawn list: a dynamic Rapier sphere with a
/// pulsing glow child. Its collider masks to `PhysicsLayers.platform`
/// only, so it rolls on the ramp without rock, player, or projectile
/// contacts. Scoped to the run: exiting `playing` despawns any pickup in
/// flight.
List<Object> shieldPickupBundle({required double x}) {
  final glow = _makeGlow();
  return [
    const Collectable(),
    const ShieldPickup(),
    ShieldPickupState(),
    ShieldPickupVisuals(glow),
    SceneNode(_makePickupNode(x, glow)),
    const PhysicsDriven(),
    const DespawnOnExit(GameStatus.playing),
  ];
}

Node _makeGlow() => Node(
  mesh: Mesh(_glowGeometry, _glowMaterial),
  localTransform: Matrix4.identity(),
)..frustumCulled = false;

Node _makePickupNode(double x, Node glow) {
  return Node(
      mesh: Mesh(_pickupGeometry, _pickupMaterial),
      localTransform: Matrix4.translation(
        Vector3(x, shieldPickupSpawnY, shieldPickupSpawnZ),
      ),
    )
    ..add(glow)
    ..addComponent(
      RapierRigidBody(
        type: BodyType.dynamic_,
        ccdEnabled: true,
        linearVelocity: Vector3(0, 0, 4),
        angularVelocity: Vector3(3, 0, 0),
      ),
    )
    ..addComponent(
      RapierCollider(
        shape: SphereShape(radius: collectableRadius),
        collisionLayer: PhysicsLayers.collectable,
        collisionMask: PhysicsLayers.platform,
      ),
    );
}
