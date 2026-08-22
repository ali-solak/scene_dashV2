part of '../creeps.dart';

List<Object> creepBundle() {
  final start = towerPath.first;
  return [
    const Creep(),
    Health(creepHealth),
    PathProgress(),
    SceneTransform(start.x, creepRadius, start.z),
    const DespawnOnExit(GameStatus.playing),
  ];
}

Node creepNode() => Node(
  mesh: Mesh(
    SphereGeometry(radius: creepRadius),
    UnlitMaterial()..baseColorFactor = creepColor,
  ),
);
