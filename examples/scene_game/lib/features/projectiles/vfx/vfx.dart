part of '../projectiles.dart';

/// A translucent additive-ish glow material for projectile and impact visuals.
PhysicallyBasedMaterial glowMaterial(Vector4 color, {double alpha = 1}) {
  final visible = Vector4(color.x, color.y, color.z, color.w * alpha);
  return PhysicallyBasedMaterial()
    ..baseColorFactor = visible
    ..emissiveFactor = Vector4(color.x * 1.6, color.y * 1.6, color.z * 1.6, 1)
    ..metallicFactor = 0
    ..roughnessFactor = 0.18
    ..alphaMode = AlphaMode.blend;
}

// PlasmaShape draws from salts 24..27, disjoint from the 20..23 range the
// stock shapes use, per the EmitterShape contract.
const int _plasmaSaltA = 24;
const int _plasmaSaltB = 25;
const int _plasmaSaltC = 26;

/// Spawns plasma motes on a spherical shell around the local origin, headed
/// inward with a tangential twist — energy spiraling into the charge orb.
/// The emitter node sits at the orb, so the convergence point is just the
/// shape's origin, and the node-local simulation moving with the player is
/// exactly what a carried charge effect wants.
final class PlasmaShape extends fx.EmitterShape {
  const PlasmaShape();

  @override
  void sample(fx.ParticleStorage storage, int index) {
    final u = storage.randomFor(index, _plasmaSaltA);
    final v = storage.randomFor(index, _plasmaSaltB);
    final w = storage.randomFor(index, _plasmaSaltC);
    // Uniform direction on the unit sphere.
    final z = u * 2 - 1;
    final planar = math.sqrt(math.max(0, 1 - z * z));
    final phi = v * math.pi * 2;
    final ox = planar * math.cos(phi), oy = planar * math.sin(phi), oz = z;
    final radius =
        chargePlasmaShellRadiusMin +
        (chargePlasmaShellRadiusMax - chargePlasmaShellRadiusMin) * w;
    storage.posX[index] = ox * radius;
    storage.posY[index] = oy * radius;
    storage.posZ[index] = oz * radius;
    // Inward radial mixed with a tangent (the world-up cross product) for
    // the spiral; the up bias keeps the swirl visually rising.
    var tx = -oy, ty = ox, tz = 0.0;
    final tLen = math.sqrt(tx * tx + ty * ty + tz * tz);
    if (tLen > 1e-5) {
      tx /= tLen;
      ty /= tLen;
      tz /= tLen;
    }
    var dx = -ox * 0.8 + tx * 0.55;
    var dy = -oy * 0.8 + ty * 0.55 + 0.18;
    var dz = -oz * 0.8 + tz * 0.55;
    final dLen = math.sqrt(dx * dx + dy * dy + dz * dz);
    storage.velX[index] = dx / dLen;
    storage.velY[index] = dy / dLen;
    storage.velZ[index] = dz / dLen;
  }
}

/// Startup (scene-gated): spawn the single charge-plasma emitter as a
/// process entity. `updateChargeVisuals` attaches its node to the current
/// player and throttles its rate with the charge; it idles at rate zero
/// the rest of the time. Constructing it here keeps GPU-side billboard
/// geometry out of headless boots, like the reticle.
void spawnChargePlasma(World world) {
  final spawner = fx.Spawner(rate: 0);
  final system = fx.ParticleSystem(
    maxParticles: chargePlasmaMaxParticles,
    shape: const PlasmaShape(),
    spawner: spawner,
    lifetime: const fx.UniformFloat(0.22, 0.38),
    startSpeed: const fx.UniformFloat(2.4, 4.0),
    // Small crisp energy dots, not glow blobs.
    startSize: const fx.UniformFloat(0.06, 0.13),
    // HDR cyan-blue: the plasma reads over the darker ramp, so additive
    // keeps its glow.
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(1.0, 1.8, 2.8, 1)),
        fx.ColorStop(1, Vector4(0.5, 1.1, 2.6, 1)),
      ]),
    ),
    modules: [
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 1, to: 0.4)),
      ),
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            fx.ColorStop(0, Vector4(1, 1, 1, 0.0)),
            fx.ColorStop(0.15, Vector4(1, 1, 1, 1)),
            fx.ColorStop(1, Vector4(1.4, 1.4, 1.6, 0)),
          ]),
        ),
      ),
    ],
    seed: chargePlasmaSeed,
  );
  final emitter = fx.ParticleEmitterComponent(
    system: system,
    material: softAdditiveSprite(),
  );
  final node =
      Node(
          localTransform: Matrix4.translation(
            Vector3(0, 0, -(playerBodyVisualRadius + 0.55)),
          ),
        )
        ..frustumCulled = false
        ..addComponent(emitter);
  world.spawn([
    const Name('charge-plasma'),
    ChargePlasmaEmitter(node: node, spawner: spawner),
  ]);
}
