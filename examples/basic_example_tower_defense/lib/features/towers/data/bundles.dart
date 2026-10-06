part of '../towers.dart';

List<Object> towerBundle(World world, TowerKind kind, Vector3 at) => [
  Tower(kind),
  Health(kind.health),
  SceneTransform.fromVector(at),
  const DespawnOnExit(GameStatus.playing),
  ...switch (kind) {
    TowerKind.bolt => [Gun()],
    TowerKind.pulse => [Pulser()],
    TowerKind.shield => [const ShieldEmitter()],
  },
  if (world.hasResource<Scene>()) ..._visuals(kind),
];

List<Object> _visuals(TowerKind kind) {
  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = switch (kind) {
      TowerKind.bolt => boltColor,
      TowerKind.pulse => pulseColor,
      TowerKind.shield => shieldTowerColor,
    }
    ..metallicFactor = 0.3
    ..roughnessFactor = 0.35;
  final node = Node(mesh: Mesh(_bodies[kind]!, material));
  return [
    NodeRef(node),
    Tint(material),
    ...switch (kind) {
      TowerKind.bolt => [_beam(node)],
      TowerKind.pulse => [_ring(node)],
      TowerKind.shield => const <Object>[],
    },
  ];
}

TowerBeam _beam(Node tower) {
  final material = _fx(beamColor);
  final node = Node(mesh: Mesh(_beamGeometry, material))..visible = false;
  tower.add(node);
  return TowerBeam(node, material);
}

PulseRing _ring(Node tower) {
  final material = _fx(ringColor);
  final node = Node(mesh: Mesh(_ringGeometry, material))..visible = false;
  tower.add(node);
  return PulseRing(node, material);
}

UnlitMaterial _fx(Vector4 color) => UnlitMaterial()
  ..baseColorFactor = color.clone()
  ..alphaMode = AlphaMode.blend;

List<Object> ghostBundle() {
  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = ghostOkColor
    ..alphaMode = AlphaMode.blend;
  final node = Node(mesh: Mesh(_bodies[TowerKind.bolt]!, material))
    ..visible = false;
  return [
    SceneTransform(0, towerRadius, 0),
    NodeRef(node),
    TowerGhost(node, material),
  ];
}

final Map<TowerKind, Geometry> _bodies = {
  TowerKind.bolt: CylinderGeometry(
    bottomRadius: towerRadius,
    topRadius: towerRadius * 0.6,
    height: towerRadius * 2,
    radialSegments: 16,
  ),
  TowerKind.pulse: CylinderGeometry(
    bottomRadius: towerRadius * 1.1,
    topRadius: towerRadius * 1.1,
    height: towerRadius * 1.2,
    radialSegments: 6,
  ),
  TowerKind.shield: CylinderGeometry(
    bottomRadius: towerRadius * 0.8,
    topRadius: 0,
    height: towerRadius * 2.6,
    radialSegments: 4,
  ),
};

final Geometry _beamGeometry = CuboidGeometry(
  Vector3(beamThickness, beamThickness, 1),
);

final Geometry _ringGeometry = TorusGeometry(radius: 1, tubeRadius: 0.06);
