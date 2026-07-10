part of '../decor.dart';

/// Startup: build the instanced pool and scatter the motes. A no-op in a
/// headless game — decoration needs a scene.
void spawnMotes(World world) {
  final scene = world.resource<Scene>();
  final field = world.resource<MoteField>();
  final pool = InstancedPool(
    geometry: SphereGeometry(radius: 0.07, segments: 8, rings: 6),
    material: PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(0.7, 0.92, 1.0, 1)
      ..emissiveFactor = Vector4(0.5, 0.85, 1.0, 1)
      ..metallicFactor = 0
      ..roughnessFactor = 0.4,
    capacity: _moteCount,
  );

  final random = math.Random(7);
  for (var i = 0; i < _moteCount; i++) {
    field.base[i * 3] = (random.nextDouble() * 2 - 1) * rampWidth * 0.5;
    field.base[i * 3 + 1] = 4 + random.nextDouble() * 5;
    field.base[i * 3 + 2] =
        -rampLength * 0.5 + random.nextDouble() * rampLength;
    field.phase[i] = random.nextDouble() * math.pi * 2;
    field.speed[i] = 0.6 + random.nextDouble() * 0.8;
  }

  field.pool = pool;
  pool.addTo(scene);
}

/// Update: bob every mote. Allocation-free — one [InstancedPool.scratch]
/// matrix is reused for all instances, and `setInstanceTransform` copies
/// its values in.
void animateMotes(World world) {
  final field = world.resource<MoteField>();
  final pool = field.pool;
  if (pool == null) return;

  final dt = world.dt;
  final scratch = pool.scratch;
  for (var i = 0; i < _moteCount; i++) {
    final p = field.phase[i] + field.speed[i] * dt;
    field.phase[i] = p;
    scratch.setTranslationRaw(
      field.base[i * 3],
      field.base[i * 3 + 1] + math.sin(p) * _moteAmplitude,
      field.base[i * 3 + 2],
    );
    pool.mesh.setInstanceTransform(i, scratch);
  }
}
