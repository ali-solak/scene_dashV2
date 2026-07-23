part of '../decor.dart';

/// Startup: scatter the motes, one PBR node each. A no-op in a headless
/// game — decoration needs a scene. The emissive PBR material is the
/// original glowing look; the geometry and material are shared across the
/// nodes so this is 48 draws of one small sphere, not 48 uploads.
void spawnMotes(World world) {
  final scene = world.resource<Scene>();
  final field = world.resource<MoteField>();
  final geometry = SphereGeometry(radius: 0.07, segments: 8, rings: 6);
  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = Vector4(0.7, 0.92, 1.0, 1)
    ..emissiveFactor = Vector4(0.5, 0.85, 1.0, 1)
    ..metallicFactor = 0
    ..roughnessFactor = 0.4;

  final random = math.Random(7);
  for (var i = 0; i < _moteCount; i++) {
    field.base[i * 3] = (random.nextDouble() * 2 - 1) * rampWidth * 0.5;
    field.base[i * 3 + 1] = 4 + random.nextDouble() * 5;
    field.base[i * 3 + 2] =
        -rampLength * 0.5 + random.nextDouble() * rampLength;
    field.phase[i] = random.nextDouble() * math.pi * 2;
    field.speed[i] = 0.6 + random.nextDouble() * 0.8;

    final node = Node(
      mesh: Mesh(geometry, material),
      localTransform: Matrix4.translation(
        Vector3(
          field.base[i * 3],
          field.base[i * 3 + 1],
          field.base[i * 3 + 2],
        ),
      ),
    )..frustumCulled = false;
    field.motes.add(node);
    scene.root.add(node);
  }
}

/// Update: bob every mote. Allocation-free — each node's own transform is
/// mutated in place.
void animateMotes(World world) {
  final field = world.resource<MoteField>();
  if (field.motes.isEmpty) return;

  final dt = world.dt;
  for (var i = 0; i < _moteCount; i++) {
    final p = field.phase[i] + field.speed[i] * dt;
    field.phase[i] = p;
    final node = field.motes[i];
    node.localTransform = node.localTransform
      ..setTranslationRaw(
        field.base[i * 3],
        field.base[i * 3 + 1] + math.sin(p) * _moteAmplitude,
        field.base[i * 3 + 2],
      );
  }
}
