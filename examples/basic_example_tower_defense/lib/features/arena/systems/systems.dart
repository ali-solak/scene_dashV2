part of '../arena.dart';

void spawnArena(World world) {
  final scene = world.resource<Scene>()
    ..environment = EnvironmentMap.studio()
    ..directionalLight = DirectionalLight(
      direction: sunDirection,
      intensity: 3.6,
      castsShadow: true,
    )
    ..toneMapping = ToneMappingMode.aces
    ..exposure = 0.8
    ..add(cameraNode())
    ..add(boardNode());
  for (final item in decor) {
    scene.add(decorNode(item));
  }
  world
    ..spawn(portalBundle())
    ..spawn(coreBundle());
}

void spin(World world) {
  world.query2<Spin, SceneTransform>().each((_, spin, at) {
    spin.angle = (spin.angle + spin.radiansPerSecond * world.dt) % (2 * pi);
    at.rotation.setAxisAngle(_up, spin.angle);
  });
}

bool onTowerPath(double x, double z) {
  final spot = Vector2(x, z);
  for (var i = 1; i < route.length; i++) {
    final a = Vector2(route[i - 1].x, route[i - 1].z);
    final b = Vector2(route[i].x, route[i].z);
    if (_distanceToSegment(spot, a, b) < pathClearance) return true;
  }
  return false;
}

bool onDecor(double x, double z, double clearance) => decor.any((item) {
  final dx = x - item.x;
  final dz = z - item.z;
  final reach = item.radius + clearance;
  return dx * dx + dz * dz < reach * reach;
});

double _distanceToSegment(Vector2 p, Vector2 a, Vector2 b) {
  final ab = b - a;
  final t = ((p - a).dot(ab) / ab.length2).clamp(0.0, 1.0);
  return p.distanceTo(a + ab * t);
}

final Vector3 _up = Vector3(0, 1, 0);
