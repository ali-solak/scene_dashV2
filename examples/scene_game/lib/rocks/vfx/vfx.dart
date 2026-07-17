part of '../rocks.dart';

/// Builds one flaming rock's trail emitter: a continuous upstream
/// [fx.ParticleEmitterComponent] on a child node, embers rising in a cone
/// and dying out behind the rock. The emitter advances with the scene tick,
/// so trails freeze under hitstop like everything else; the fixed [seed]
/// makes every replay visually identical.
Node buildFlameTrailEmitter() {
  final system = fx.ParticleSystem(
    maxParticles: rockTrailMaxParticles,
    shape: fx.ConeShape(angle: 0.5, radius: rockRadius * 0.4),
    spawner: fx.Spawner(rate: rockTrailEmberRate),
    lifetime: const fx.UniformFloat(0.28, 0.55),
    startSpeed: const fx.UniformFloat(1.0, 2.2),
    startSize: fx.UniformFloat(rockRadius * 0.28, rockRadius * 0.5),
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(1.0, 0.55, 0.12, 1)),
        fx.ColorStop(1, Vector4(1.0, 0.30, 0.05, 1)),
      ]),
    ),
    modules: [
      // Embers shrink and cool to nothing instead of popping out.
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 1, to: 0.1)),
      ),
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            fx.ColorStop(0, Vector4(1.0, 0.55, 0.12, 0.9)),
            fx.ColorStop(0.6, Vector4(0.9, 0.25, 0.05, 0.5)),
            fx.ColorStop(1, Vector4(0.3, 0.05, 0.02, 0)),
          ]),
        ),
      ),
      fx.LinearDragModule(1.2),
    ],
    gravity: Vector3(0, 2.4, 0), // hot embers drift up
    seed: rockTrailSeed,
  );
  // Soft round sprites, not hard billboard squares.
  final emitter = fx.ParticleEmitterComponent(
    system: system,
    material: softAdditiveSprite(),
  );
  return Node()
    ..frustumCulled = false
    ..addComponent(emitter);
}
