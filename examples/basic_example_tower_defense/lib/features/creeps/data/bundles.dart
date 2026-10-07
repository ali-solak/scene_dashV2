part of '../creeps.dart';

List<Object> runnerBundle(World world, {double scale = 1, int index = 0}) => [
  ..._creep(world, runnerRadius, index),
  if (world.hasResource<Scene>()) ..._visuals(_runnerGeometry, runnerColor),
  Health(runnerHealth * scale),
  const Bounty(runnerBounty),
  Speed(creepSpeed),
];

List<Object> raiderBundle(World world, {double scale = 1, int index = 0}) => [
  ..._creep(world, raiderRadius, index),
  if (world.hasResource<Scene>()) ..._visuals(_raiderGeometry, raiderColor),
  Health(raiderHealth * scale),
  const Bounty(raiderBounty),
  Speed(raiderSpeed),
  Raider(),
];

List<Object> _creep(World world, double radius, int index) {
  final angle = index * spawnTurn;
  final start = route.first;
  return [
    const Creep(),
    PathProgress(),
    SceneTransform(
      start.x + cos(angle) * spawnScatter,
      radius,
      start.z + sin(angle) * spawnScatter,
    ),
    const DespawnOnExit(GameStatus.playing),
  ];
}

List<Object> _visuals(Geometry geometry, Vector4 color) {
  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = color
    ..roughnessFactor = 0.5;
  return [NodeRef(Node(mesh: Mesh(geometry, material))), Tint(material)];
}

final Geometry _runnerGeometry = SphereGeometry(radius: runnerRadius);

final Geometry _raiderGeometry = IcosphereGeometry(
  radius: raiderRadius,
  subdivisions: 1,
);
