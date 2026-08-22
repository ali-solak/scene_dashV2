part of '../towers.dart';

List<Object> towerBundle(Vector3 at) => [
  Tower(),
  SceneTransform.fromVector(at),
  const DespawnOnExit(GameStatus.playing),
];

(NodeRef, TowerBeam) towerVisuals() {
  final node = Node(
    mesh: Mesh(
      CuboidGeometry(Vector3.all(towerRadius * 2)),
      UnlitMaterial()..baseColorFactor = towerColor,
    ),
  );
  final beamMaterial = UnlitMaterial()
    ..baseColorFactor = beamColor
    ..alphaMode = AlphaMode.blend;
  final beam = Node(
    mesh: Mesh(
      CuboidGeometry(Vector3(beamThickness, beamThickness, 1)),
      beamMaterial,
    ),
  )..visible = false;
  node.add(beam);
  return (NodeRef(node), TowerBeam(beam, beamMaterial));
}
