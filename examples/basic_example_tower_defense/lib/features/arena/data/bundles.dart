part of '../arena.dart';

Node cameraNode() =>
    Node(localTransform: Node.lookAtTransform(cameraEye, Vector3.zero()))
      ..addComponent(
        CameraComponent(
          projection: OrthographicProjection(
            size: const OrthographicSize.contain(viewWidth, viewHeight),
          ),
          activateOnMount: true,
        ),
      );

Node boardNode() => Node(name: 'board')
  ..add(
    Node(
      mesh: Mesh(
        CuboidGeometry(
          Vector3(boardHalfSize * 2, boardThickness, boardHalfSize * 2),
        ),
        _lit(cliffColor, roughness: 1),
      ),
      localTransform: Matrix4.translation(
        Vector3(0, -boardThickness / 2 - 0.2, 0),
      ),
    ),
  )
  ..add(
    Node(
      name: groundNodeName,
      mesh: Mesh(
        CuboidGeometry(Vector3(boardHalfSize * 2, 0.2, boardHalfSize * 2)),
        _lit(grassColor, roughness: 0.95),
      ),
      localTransform: Matrix4.translation(Vector3(0, -0.1, 0)),
    ),
  )
  ..add(
    Node(
      mesh: Mesh(
        RibbonGeometry(
          CatmullRomPath(pathPoints),
          width: pathWidth,
          stations: 160,
        ),
        _lit(roadColor, roughness: 0.9),
      ),
      localTransform: Matrix4.translation(Vector3(0, 0.02, 0)),
    ),
  );

Node decorNode(Decor item) {
  final node = switch (item.kind) {
    DecorKind.tree => _tree(item.radius),
    DecorKind.rock => _rock(item.radius),
    DecorKind.pond => _pond(item.radius),
  };
  return node..localTransform = Matrix4.translation(Vector3(item.x, 0, item.z));
}

List<Object> portalBundle() => [
  Spin(1.2),
  SceneTransform.fromVector(route.first + Vector3(0, 1.4, 0)),
  NodeRef(
    Node()..add(
      Node(
        mesh: Mesh(
          TorusGeometry(radius: 1.3, tubeRadius: 0.22),
          _glow(portalGlow),
        ),
        localTransform: Matrix4.rotationX(pi / 2),
      ),
    ),
  ),
];

List<Object> coreBundle() => [
  Spin(0.8),
  SceneTransform.fromVector(route.last + Vector3(0, 1.3, 0)),
  NodeRef(
    Node(
      mesh: Mesh(
        IcosphereGeometry(radius: 1.0, subdivisions: 0),
        _glow(coreGlow),
      ),
    ),
  ),
];

Node _tree(double size) => Node()
  ..add(
    Node(
      mesh: Mesh(
        CylinderGeometry(
          bottomRadius: size * 0.18,
          topRadius: size * 0.14,
          height: size * 1.2,
          radialSegments: 8,
        ),
        _lit(trunkColor),
      ),
      localTransform: Matrix4.translation(Vector3(0, size * 0.6, 0)),
    ),
  )
  ..add(
    Node(
      mesh: Mesh(
        CylinderGeometry(
          bottomRadius: size,
          topRadius: 0,
          height: size * 2.4,
          radialSegments: 8,
        ),
        _lit(leafColor),
      ),
      localTransform: Matrix4.translation(Vector3(0, size * 2.2, 0)),
    ),
  );

Node _rock(double size) => Node(
  mesh: Mesh(
    IcosphereGeometry(radius: size, subdivisions: 0),
    _lit(rockColor, roughness: 0.8),
  ),
  localTransform: Matrix4.translation(Vector3(0, size * 0.35, 0)),
);

Node _pond(double size) => Node(
  mesh: Mesh(
    CylinderGeometry(
      bottomRadius: size,
      topRadius: size,
      height: 0.05,
      radialSegments: 32,
    ),
    _lit(waterColor, roughness: 0.1),
  ),
  localTransform: Matrix4.translation(Vector3(0, 0.03, 0)),
);

PhysicallyBasedMaterial _lit(Vector4 color, {double roughness = 0.7}) =>
    PhysicallyBasedMaterial()
      ..baseColorFactor = color
      ..roughnessFactor = roughness;

PhysicallyBasedMaterial _glow(Vector4 glow) => PhysicallyBasedMaterial()
  ..baseColorFactor = Vector4(0.1, 0.1, 0.12, 1)
  ..emissiveFactor = glow
  ..roughnessFactor = 0.3;
