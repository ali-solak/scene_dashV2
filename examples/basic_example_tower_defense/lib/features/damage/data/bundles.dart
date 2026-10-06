part of '../damage.dart';

List<Object> popBundle(World world, Vector3 at) => [
  const Pop(),
  SceneTransform.fromVector(at),
  DespawnAfter(popSeconds),
  if (world.hasResource<Scene>())
    NodeRef(Node(mesh: Mesh(_popGeometry, _popMaterial))),
];

ShieldBubble shieldBubble() {
  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = shieldColor
    ..emissiveFactor = shieldColor
    ..alphaMode = AlphaMode.blend;
  return ShieldBubble(Node(mesh: Mesh(_bubbleGeometry, material)), material);
}

final Geometry _popGeometry = IcosphereGeometry(radius: 0.4, subdivisions: 1);

final Geometry _bubbleGeometry = SphereGeometry(radius: shieldBubbleRadius);

final Material _popMaterial = UnlitMaterial()..baseColorFactor = popColor;
