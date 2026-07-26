part of '../player.dart';

/// The player's spawn list: a kinematic sphere driven by Rapier's
/// character controller. `PhysicsDriven` tells the generic transform sync
/// to leave the node alone; the feedback nodes are built once and attached
/// as children — one visuals component per writing feature (legs, charge,
/// shield), so each system's access declaration names only what it owns.
List<Object> playerBundle() {
  final (legs, charge, shield) = buildPlayerVisuals();
  return [
    const Player(),
    SceneNode(_makePlayerNode(legs, charge, shield)),
    const PhysicsDriven(),
    legs,
    charge,
    shield,
  ];
}

Node _makePlayerNode(
  PlayerVisuals legs,
  PlayerChargeVisuals charge,
  PlayerShieldVisuals shield,
) {
  final playerMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = Vector4(0.05, 0.54, 1.0, 1)
    ..metallicFactor = 0.28
    ..roughnessFactor = 0.18
    ..emissiveFactor = Vector4(0.0, 0.14, 0.32, 1);
  final markerMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = Vector4(1, 1, 1, 1)
    ..metallicFactor = 0.12
    ..roughnessFactor = 0.2
    ..emissiveFactor = Vector4(0.55, 0.72, 1.0, 1);

  final root =
      Node(
          mesh: Mesh(
            SphereGeometry(radius: playerBodyVisualRadius),
            playerMaterial,
          ),
          localTransform: Matrix4.translation(
            Vector3(0, playerStartY, playerStartZ),
          ),
        )
        ..add(
          Node(
            mesh: Mesh(
              CuboidGeometry(Vector3(0.18, 0.18, playerBodyVisualRadius * 1.6)),
              markerMaterial,
            ),
            localTransform: Matrix4.translation(
              Vector3(0, playerBodyVisualRadius, 0),
            ),
          ),
        )
        ..addComponent(RapierRigidBody(type: BodyType.kinematic))
        ..addComponent(
          RapierCollider(
            shape: SphereShape(radius: playerCollisionRadius),
            collisionLayer: PhysicsLayers.player,
          ),
        )
        ..addComponent(
          RapierKinematicCharacterController(
            up: Vector3(0, 1, 0),
            slide: true,
            snapToGround: 0.5,
            autostep: true,
          ),
        );

  legs.attachTo(root);
  charge.attachTo(root);
  shield.attachTo(root);
  return root;
}
