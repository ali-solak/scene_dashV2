part of '../arena.dart';

void spawnArena(World world) {
  final scene = world.resource<Scene>()
    ..add(cameraNode())
    ..add(groundNode());
  for (var i = 1; i < towerPath.length; i++) {
    scene.add(laneMarkerNode(towerPath[i - 1], towerPath[i]));
  }
}

bool onTowerPath(double x, double z) {
  final spot = Vector3(x, 0, z);
  for (var i = 1; i < towerPath.length; i++) {
    final lane = segmentBox(towerPath[i - 1], towerPath[i], _clearance);
    if (lane.intersectsWithVector3(spot)) return true;
  }
  return false;
}

final Vector3 _clearance = Vector3.all(pathClearance);
