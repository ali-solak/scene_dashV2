part of '../decor.dart';

/// Startup: scatter the leaves through the column above the clearing, one
/// node each. A no-op headless: decoration needs a scene.
///
/// The quad and the leaf mask are shared; only the tint materials differ,
/// so this is [_leafCount] draws of two triangles rather than
/// [_leafCount] uploads.
void spawnLeaves(World world) {
  final scene = world.resource<Scene>();
  final field = world.resource<LeafField>();
  final geometry = _leafQuad();

  // A few tints, cycled: the clearing is deciduous, not autumnal, so
  // these stay in the greens with a couple of turning leaves for relief.
  final materials = [
    _leafMaterial(Vector4(0.42, 0.55, 0.20, 1)),
    _leafMaterial(Vector4(0.30, 0.44, 0.16, 1)),
    _leafMaterial(Vector4(0.55, 0.48, 0.18, 1)),
    _leafMaterial(Vector4(0.62, 0.38, 0.14, 1)),
  ];

  final random = math.Random(31);
  for (var i = 0; i < _leafCount; i++) {
    // Area-uniform scatter in the column, or they bunch at the middle.
    final radius = _leafFieldRadius * math.sqrt(random.nextDouble());
    final theta = random.nextDouble() * math.pi * 2;
    field.position[i * 3] = math.cos(theta) * radius;
    field.position[i * 3 + 1] = random.nextDouble() * _leafCeiling;
    field.position[i * 3 + 2] = math.sin(theta) * radius;

    field.fall[i] =
        _fallSlowest + random.nextDouble() * (_fallFastest - _fallSlowest);
    field.tumble[i] =
        (_tumbleSlowest +
            random.nextDouble() * (_tumbleFastest - _tumbleSlowest)) *
        (random.nextBool() ? 1 : -1);
    field.sway[i] =
        _swaySlowest + random.nextDouble() * (_swayFastest - _swaySlowest);
    field.phase[i] = random.nextDouble() * math.pi * 2;
    field.spin[i] = random.nextDouble() * math.pi * 2;

    // A random tumble axis, so leaves turn over rather than spinning like
    // pinwheels on one plane.
    final ax = random.nextDouble() * 2 - 1;
    final ay = random.nextDouble() * 2 - 1;
    final az = random.nextDouble() * 2 - 1;
    final length = math.sqrt(ax * ax + ay * ay + az * az).clamp(1e-3, 10.0);
    field.axis[i * 3] = ax / length;
    field.axis[i * 3 + 1] = ay / length;
    field.axis[i * 3 + 2] = az / length;

    final node = Node(mesh: Mesh(geometry, materials[i % materials.length]))
      ..frustumCulled = false;
    field.leaves.add(node);
    scene.add(node);
  }
}

/// Update: fall, sway, tumble, and wrap back to the ceiling.
///
/// Allocation-free per leaf; each node's transform is rewritten in
/// place. Reads the fight's [WindState], so the drift picks up when the
/// pack circles and settles when one telegraphs.
void animateLeaves(World world) {
  final field = world.resource<LeafField>();
  if (field.leaves.isEmpty) return;

  final dt = world.dt;
  final wind = world.hasResource<WindState>()
      ? world.resource<WindState>().strength
      : 1.0;
  final windX = windDirection.x * wind * _windPush;
  final windZ = windDirection.y * wind * _windPush;

  for (var i = 0; i < _leafCount; i++) {
    final phase = field.phase[i] + field.sway[i] * dt;
    field.phase[i] = phase;
    field.spin[i] = field.spin[i] + field.tumble[i] * dt;

    // The sway is perpendicular to the wind, so a leaf slaloms across the
    // drift instead of just wobbling along it.
    final slalom = math.sin(phase) * _swayAmplitude;
    var x = field.position[i * 3] + (windX - windZ * slalom * 0.35) * dt;
    var y = field.position[i * 3 + 1] - field.fall[i] * dt;
    var z = field.position[i * 3 + 2] + (windZ + windX * slalom * 0.35) * dt;

    // Landed, or blown off the field: back to the ceiling somewhere new.
    // Recycling beats spawning; the count stays flat all run.
    if (y <= 0 || (x * x + z * z) > _leafFieldRadius * _leafFieldRadius) {
      final radius = _leafFieldRadius * math.sqrt(_wrapRandom.nextDouble());
      final theta = _wrapRandom.nextDouble() * math.pi * 2;
      x = math.cos(theta) * radius;
      z = math.sin(theta) * radius;
      y = _leafCeiling;
    }

    field.position[i * 3] = x;
    field.position[i * 3 + 1] = y;
    field.position[i * 3 + 2] = z;

    final node = field.leaves[i];
    final transform = node.localTransform;
    _setLeafTransform(
      transform,
      x: x,
      y: y,
      z: z,
      axisX: field.axis[i * 3],
      axisY: field.axis[i * 3 + 1],
      axisZ: field.axis[i * 3 + 2],
      angle: field.spin[i],
    );
    node.localTransform = transform;
  }
}

void _setLeafTransform(
  Matrix4 transform, {
  required double x,
  required double y,
  required double z,
  required double axisX,
  required double axisY,
  required double axisZ,
  required double angle,
}) {
  final cosAngle = math.cos(angle);
  final sinAngle = math.sin(angle);
  final oneMinusCos = 1 - cosAngle;
  final storage = transform.storage;

  storage[0] = oneMinusCos * axisX * axisX + cosAngle;
  storage[1] = oneMinusCos * axisX * axisY + sinAngle * axisZ;
  storage[2] = oneMinusCos * axisX * axisZ - sinAngle * axisY;
  storage[3] = 0;
  storage[4] = oneMinusCos * axisX * axisY - sinAngle * axisZ;
  storage[5] = oneMinusCos * axisY * axisY + cosAngle;
  storage[6] = oneMinusCos * axisY * axisZ + sinAngle * axisX;
  storage[7] = 0;
  storage[8] = oneMinusCos * axisX * axisZ + sinAngle * axisY;
  storage[9] = oneMinusCos * axisY * axisZ - sinAngle * axisX;
  storage[10] = oneMinusCos * axisZ * axisZ + cosAngle;
  storage[11] = 0;
  storage[12] = x;
  storage[13] = y;
  storage[14] = z;
  storage[15] = 1;
}

/// Respawn jitter. Seeded, so a run is reproducible.
final math.Random _wrapRandom = math.Random(97);

/// One leaf: a quad carrying the mask, emitted both ways round. A
/// translucent material is always back-face culled whatever
/// `doubleSided` says, and a tumbling leaf is seen from either face;
/// without the second winding it would blink out for half its rotation.
MeshGeometry _leafQuad() {
  const half = _leafSize;
  final positions = Float32List.fromList([
    -half, 0, 0, //
    half, 0, 0, //
    -half, _leafSize * 2, 0, //
    half, _leafSize * 2, 0,
  ]);
  final texCoords = Float32List.fromList([
    0, 1, //
    1, 1, //
    0, 0, //
    1, 0,
  ]);
  return MeshGeometry.fromArrays(
    positions: positions,
    texCoords: texCoords,
    indices: const [0, 1, 2, 1, 3, 2, 2, 1, 0, 2, 3, 1],
  );
}

Material _leafMaterial(Vector4 tint) =>
    UnlitMaterial(colorTexture: leafTexture())
      ..baseColorFactor = tint
      ..alphaMode = AlphaMode.blend;
