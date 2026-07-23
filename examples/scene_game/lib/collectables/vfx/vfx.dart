part of '../collectables.dart';

/// Spawns one shield-deflection burst at [position]: a short-lived entity
/// whose node carries an upstream particle emitter — bright shards thrown
/// up and out where the rock bounced off the bubble. The entity's
/// [DespawnAfter] is the whole cleanup; run-scoped like every other spawn.
///
/// A no-op headless (`hasResource<Scene>`): emitter construction builds
/// GPU-side billboard geometry, and the burst is scene-side anyway — the
/// deflection logic that calls this stays fully testable.
void spawnDeflectBurst(World world, Vector3 position) {
  if (!world.hasResource<Scene>()) return;
  final system = fx.ParticleSystem(
    maxParticles: deflectBurstCount,
    // Shards leave the bubble's upper half, headed outward.
    shape: const fx.SphereShape(radius: 0.2, hemisphere: true),
    spawner: fx.Spawner(
      bursts: [fx.ParticleBurst(time: 0, count: deflectBurstCount)],
    ),
    looping: false,
    duration: 0.1,
    lifetime: const fx.UniformFloat(0.2, 0.4),
    startSpeed: const fx.UniformFloat(2.0, 4.0),
    startSize: const fx.UniformFloat(0.12, 0.24),
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(0.6, 0.95, 1.0, 1)),
        fx.ColorStop(1, Vector4(0.45, 0.8, 1.0, 1)),
      ]),
    ),
    modules: [
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 1, to: 0.3)),
      ),
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            fx.ColorStop(0, Vector4(1, 1, 1, 1)),
            fx.ColorStop(1, Vector4(1, 1, 1, 0)),
          ]),
        ),
      ),
      fx.LinearDragModule(2.5),
    ],
    gravity: Vector3(0, -3, 0),
    seed: deflectBurstSeed,
  );
  final emitter =
      fx.ParticleEmitterComponent(
          system: system,
          material: softAdditiveSprite(),
        )
        ..facing = BillboardFacing.velocityStretched
        ..velocityStretch = 0.03;
  final node = Node(localTransform: Matrix4.translation(position))
    ..frustumCulled = false
    ..addComponent(emitter);
  world.spawn([
    const Name('deflect-burst'),
    SceneNode(node),
    DespawnAfter(deflectBurstEntityLifetime),
    const DespawnOnExit(GameStatus.playing),
  ]);
}
