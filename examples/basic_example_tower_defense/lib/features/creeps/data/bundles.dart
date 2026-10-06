part of '../creeps.dart';

List<Object> creepBundle(World world) {
  final start = towerPath.first;
  return [
    const Creep(),
    Health(creepHealth),
    PathProgress(),
    SceneTransform(start.x, creepRadius, start.z),
    const DespawnOnExit(GameStatus.playing),
    if (world.hasResource<Scene>()) NodeRef(creepNode()),
  ];
}

Node creepNode() => Node(
  mesh: Mesh(
    SphereGeometry(radius: creepRadius),
    UnlitMaterial()..baseColorFactor = creepColor,
  ),
);
