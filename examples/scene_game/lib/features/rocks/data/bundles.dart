part of '../rocks.dart';

final Material _rockMaterial = PhysicallyBasedMaterial()
  ..baseColorFactor = Vector4(0.42, 0.24, 0.18, 1)
  ..metallicFactor = 0.12
  ..roughnessFactor = 0.48;

final Material _flamingMaterial = PhysicallyBasedMaterial()
  ..baseColorFactor = Vector4(0.72, 0.22, 0.08, 1)
  ..emissiveFactor = Vector4(0.18, 0.04, 0.0, 1)
  ..metallicFactor = 0.18
  ..roughnessFactor = 0.26;

final Material _shellMaterial = PhysicallyBasedMaterial()
  ..baseColorFactor = Vector4(1.0, 0.95, 0.7, 0.5)
  ..emissiveFactor = Vector4(1.2, 1.0, 0.6, 1)
  ..metallicFactor = 0
  ..roughnessFactor = 0.2
  ..alphaMode = AlphaMode.blend;

final _rockGeometry = SphereGeometry(radius: rockRadius);
final _shellGeometry = SphereGeometry(radius: rockRadius * 1.12);

List<Object> rockBundle({required double x, bool flaming = false}) {
  final shell = _makeShell();
  return [
    NodeRef(_makeRockNode(x, flaming, shell)),
    const PhysicsDriven(),
    const DespawnOnExit(GameStatus.playing),
    const DespawnOutside(minY: rockKillY),
    const Rock(),
    if (flaming) const Flaming(),
    RockVisuals(shell),
  ];
}

void igniteRock(World world, Entity entity, Flaming flaming) {
  final node = world.tryGet<NodeRef>(entity)?.node;
  if (node == null) return;
  node.mesh = Mesh(_rockGeometry, _flamingMaterial);
}

void extinguishRock(World world, Entity entity, Flaming flaming) {
  final node = world.tryGet<NodeRef>(entity)?.node;
  if (node == null) return;
  node.mesh = Mesh(_rockGeometry, _rockMaterial);
}

Node _makeShell() {
  return Node(
    mesh: Mesh(_shellGeometry, _shellMaterial),
    localTransform: Matrix4.identity()..scaleByDouble(0, 0, 0, 1),
  )..frustumCulled = false;
}

Node _makeRockNode(double x, bool flaming, Node shell) {
  // The Flaming observer owns the material.
  final node = Node(
    mesh: Mesh(_rockGeometry, _rockMaterial),
    localTransform: Matrix4.translation(Vector3(x, rockSpawnY, rockSpawnZ)),
  )..add(shell);
  return node
    ..addComponent(
      RigidBody(
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

Collider buildRockCollider() => Collider(
  shape: SphereShape(radius: rockRadius),
  collisionLayer: PhysicsLayers.rock,
);
