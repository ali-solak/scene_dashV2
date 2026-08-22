part of '../arena.dart';

Node cameraNode() =>
    Node(localTransform: Node.lookAtTransform(cameraEye, Vector3.zero()))
      ..addComponent(CameraComponent(activateOnMount: true));

Node groundNode() => _slab(_ground, groundColor)..name = groundNodeName;

Node laneMarkerNode(Vector3 a, Vector3 b) =>
    _slab(segmentBox(a, b, _markerGrowth), pathColor);

Node _slab(Aabb3 box, Vector4 color) => Node(
  mesh: Mesh(
    CuboidGeometry(box.max - box.min),
    UnlitMaterial()..baseColorFactor = color,
  ),
  localTransform: Matrix4.translation(box.center),
);

final Aabb3 _ground = Aabb3.centerAndHalfExtents(
  Vector3(0, -0.1, 0),
  Vector3(arenaHalfSize, 0.1, arenaHalfSize),
);

final Vector3 _markerGrowth = Vector3(
  pathWidth / 2,
  pathMarkerThickness / 2,
  pathWidth / 2,
);
