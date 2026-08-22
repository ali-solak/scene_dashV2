part of '../arena.dart';

void spawnArena(World world) {
  final scene = world.resource<Scene>()
    ..add(cameraNode())
    ..add(groundNode());
  for (var i = 1; i < towerPath.length; i++) {
    scene.add(laneMarkerNode(towerPath[i - 1], towerPath[i]));
  }
}

Vector3? groundPointAt(World world, Offset localPosition, Size viewSize) {
  final scene = world.resource<Scene>();
  final camera = scene.camera;
  if (camera == null) return null;
  final ray = camera.screenPointToRay(localPosition, viewSize);
  return scene
      .raycast(ray, where: (node) => node.name == groundNodeName)
      ?.worldPoint;
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
