part of '../projectiles.dart';

/// Spawns one impact burst at [position]: a short-lived entity whose node
/// carries an upstream particle emitter — velocity-stretched sparks from a
/// point, cyan for pellets, violet and bigger for charged hits
/// ([strength] > 0). The entity's [DespawnAfter] is the whole cleanup: the
/// built-in ticker despawns it after the last particle dies, and the node
/// (emitter included) unmounts with it. Run-scoped like every other spawn.
///
/// A no-op headless (`hasResource<Scene>`): emitter construction builds
/// GPU-side billboard geometry, and the burst is scene-side anyway — the
/// hit logic that calls this stays fully testable.
void spawnImpactBurst(World world, Vector3 position, {double strength = 0}) {
  if (!world.hasResource<Scene>()) return;
  final charged = strength > 0;
  final s = strength.clamp(0.0, 1.0).toDouble();
  final system = fx.ParticleSystem(
    maxParticles: charged ? chargedImpactBurstCount : impactBurstCount,
    // A zero-radius sphere degenerates to a point emitting uniformly in
    // all directions — the plan-pinned point-burst shape.
    shape: const fx.SphereShape(radius: 0),
    spawner: fx.Spawner(
      bursts: [
        fx.ParticleBurst(
          time: 0,
          count: charged ? chargedImpactBurstCount : impactBurstCount,
        ),
      ],
    ),
    looping: false,
    duration: 0.1,
    lifetime: charged
        ? const fx.UniformFloat(0.2, 0.42)
        : const fx.UniformFloat(0.14, 0.26),
    startSpeed: charged
        ? fx.UniformFloat(3.0 + 3.0 * s, 6.5 + 4.0 * s)
        : const fx.UniformFloat(2.2, 4.5),
    startSize: charged
        ? fx.UniformFloat(0.16 + 0.12 * s, 0.3 + 0.2 * s)
        : const fx.UniformFloat(0.1, 0.2),
    startColor: fx.GradientColor(
      fx.ColorGradient(
        charged
            ? [
                fx.ColorStop(0, Vector4(0.85, 0.55, 1.0, 1)),
                fx.ColorStop(1, Vector4(0.6, 0.35, 1.0, 1)),
              ]
            : [
                fx.ColorStop(0, Vector4(0.56, 0.92, 1.0, 1)),
                fx.ColorStop(1, Vector4(0.3, 0.7, 1.0, 1)),
              ],
      ),
    ),
    modules: [
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 1, to: 0.25)),
      ),
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            fx.ColorStop(0, Vector4(1, 1, 1, 1)),
            fx.ColorStop(1, Vector4(1, 1, 1, 0)),
          ]),
        ),
      ),
      fx.LinearDragModule(3.5),
    ],
    gravity: Vector3(0, -4, 0),
    seed: charged ? chargedImpactBurstSeed : impactBurstSeed,
  );
  final emitter = fx.ParticleEmitterComponent(
    system: system,
    material: softAdditiveSprite(),
  )
    ..facing = BillboardFacing.velocityStretched
    ..velocityStretch = 0.04;
  final node = Node(localTransform: Matrix4.translation(position))
    ..frustumCulled = false
    ..addComponent(emitter);
  world.spawn([
    const Name('impact-burst'),
    SceneNode(node),
    DespawnAfter(impactBurstEntityLifetime),
    const DespawnOnExit(GameStatus.playing),
  ]);
}
