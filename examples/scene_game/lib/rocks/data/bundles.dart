part of '../rocks.dart';

// Geometry and materials are shared across spawns — rocks are the
// highest-churn entity.
final Material _rockMaterial = PhysicallyBasedMaterial()
  ..baseColorFactor = Vector4(0.42, 0.24, 0.18, 1)
  ..metallicFactor = 0.12
  ..roughnessFactor = 0.48;

final Material _flamingMaterial = PhysicallyBasedMaterial()
  ..baseColorFactor = Vector4(0.72, 0.22, 0.08, 1)
  ..emissiveFactor = Vector4(0.18, 0.04, 0.0, 1)
  ..metallicFactor = 0.18
  ..roughnessFactor = 0.26;

// Only the shell's transform scale changes per hit, so this material is
// shared and never mutated per rock.
final Material _shellMaterial = PhysicallyBasedMaterial()
  ..baseColorFactor = Vector4(1.0, 0.95, 0.7, 0.5)
  ..emissiveFactor = Vector4(1.2, 1.0, 0.6, 1)
  ..metallicFactor = 0
  ..roughnessFactor = 0.2
  ..alphaMode = AlphaMode.blend;

final _rockGeometry = SphereGeometry(radius: rockRadius);
final _shellGeometry = SphereGeometry(radius: rockRadius * 1.12);

/// A dynamic rock's spawn list. Rapier owns its node transform, hence
/// `PhysicsDriven`; each rock carries a hidden flash shell child for the
/// hit flash, and every rock is scoped to the run.
List<Object> rockBundle({required double x, bool flaming = false}) {
  final shell = _makeShell();
  return [
    SceneNode(_makeRockNode(x, flaming, shell)),
    const PhysicsDriven(),
    const DespawnOnExit(GameStatus.playing),
    const Rock(),
    if (flaming) const Flaming(),
    RockVisuals(shell),
  ];
}

Node _makeShell() {
  return Node(
    mesh: Mesh(_shellGeometry, _shellMaterial),
    localTransform: Matrix4.identity()..scaleByDouble(0, 0, 0, 1),
  )..frustumCulled = false;
}

Node _makeRockNode(double x, bool flaming, Node shell) {
  final node = Node(
    mesh: Mesh(_rockGeometry, flaming ? _flamingMaterial : _rockMaterial),
    localTransform: Matrix4.translation(Vector3(x, rockSpawnY, rockSpawnZ)),
  )..add(shell);
  return node
    ..addComponent(
      RapierRigidBody(
        type: BodyType.dynamic_,
        ccdEnabled: true,
        linearVelocity: flaming
            ? Vector3(0, 0, flamingRockForwardVelocity)
            : Vector3.zero(),
        angularVelocity: flaming
            ? Vector3(flamingRockSpinVelocity, 0, 0)
            : Vector3.zero(),
      ),
    )
    ..addComponent(buildRockCollider());
}

/// Tagged with `PhysicsLayers.rock` so overlap hits can be classified by
/// collider layer; the collision *mask* stays permissive (default).
RapierCollider buildRockCollider() => RapierCollider(
      shape: SphereShape(radius: rockRadius),
      collisionLayer: PhysicsLayers.rock,
    );
