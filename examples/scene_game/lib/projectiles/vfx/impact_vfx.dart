part of '../projectiles.dart';

/// Startup: build the impact pools. Gated on the scene at registration
/// (`runIf: hasResource<Scene>()`), so headless boots skip it.
void spawnImpactVfx(World world) {
  final scene = world.resource<Scene>();
  final vfx = world.resource<ImpactVfx>();
  vfx.sparkPool = InstancedPool(
    geometry: SphereGeometry(radius: 0.22, segments: 12, rings: 6),
    material: glowMaterial(Vector4(0.56, 0.92, 1.0, 0.4), alpha: 0.4),
    capacity: _sparkCapacity,
  )..addTo(scene);
  vfx.chargedSparkPool = InstancedPool(
    geometry: SphereGeometry(radius: 0.26, segments: 12, rings: 6),
    material: glowMaterial(Vector4(0.78, 0.5, 1.0, 0.5), alpha: 0.5),
    capacity: _chargedCapacity,
  )..addTo(scene);
  vfx.ringPool = InstancedPool(
    geometry: ringGeometry(thickness: 0.16),
    material: glowMaterial(Vector4(0.44, 0.82, 1.0, 0.28), alpha: 0.28),
    capacity: _ringCapacity,
  )..addTo(scene);
}

void updateImpactVfx(World world) {
  final vfx = world.resource<ImpactVfx>();
  final dt = world.dt;
  _advanceBurst(
    vfx.sparkPool,
    vfx.sparkAge,
    vfx.sparkOrigin,
    dt,
    duration: _sparkDuration,
    startScale: 0.45,
    endScale: 1.15,
    floatUp: 0.3,
    spin: 0.8,
  );
  _advanceBurst(
    vfx.chargedSparkPool,
    vfx.chargedAge,
    vfx.chargedOrigin,
    dt,
    duration: _chargedDuration,
    startScale: 0.55,
    endScale: 1.5,
    floatUp: 0.5,
    spin: 1.3,
    strength: vfx.chargedStrength,
    strengthSize: 1.1,
  );
  _advanceBurst(
    vfx.ringPool,
    vfx.ringAge,
    vfx.ringOrigin,
    dt,
    duration: _ringDuration,
    startScale: 0.4,
    endScale: 1.8,
    spin: 0.7,
    strength: vfx.ringStrength,
    strengthSize: 1.4,
  );
}

/// Ages each live instance and writes its grow-then-pop transform; free slots
/// (age past [duration]) are already hidden and skipped.
void _advanceBurst(
  InstancedPool? pool,
  Float32List age,
  Float32List origin,
  double dt, {
  required double duration,
  required double startScale,
  required double endScale,
  double floatUp = 0,
  double spin = 0,
  Float32List? strength,
  double strengthSize = 0,
}) {
  if (pool == null) return;
  final scratch = pool.scratch;
  for (var i = 0; i < age.length; i++) {
    final a = age[i];
    if (a >= duration) continue;
    final next = a + dt;
    age[i] = next;
    final t = (next / duration).clamp(0.0, 1.0);
    final ease = 1 - math.pow(1 - t, 3).toDouble();
    final fade = (1 - t) * (1 - t);
    final boost = strength == null ? 1.0 : 1 + strengthSize * strength[i];
    final s = (startScale + (endScale - startScale) * ease) * fade * boost;
    scratch
      ..setIdentity()
      ..setTranslationRaw(
        origin[i * 3],
        origin[i * 3 + 1] + floatUp * ease,
        origin[i * 3 + 2],
      )
      ..rotateY(spin * t)
      ..scaleByDouble(s, s, s, 1);
    pool.mesh.setInstanceTransform(i, scratch);
  }
}
