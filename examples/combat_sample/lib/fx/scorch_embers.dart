/// Embers drifting off freshly burnt grass.
library;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../features/world/data/config.dart' show windDirection;
import 'particle_texture.dart';
import 'particles.dart' as fx;

const int _emberCount = 80;
const double _emberSeconds = 5.5;

/// Seeds a scorch with embers: a first lick of flame, then coals winking
/// out over the next few seconds.
void spawnScorchEmbers(World world, Vector3 center, double radius) {
  if (!world.hasResource<Scene>()) return;

  final system = fx.ParticleSystem(
    maxParticles: _emberCount,
    // A flat slab: they smoulder across the patch, not in a ball.
    shape: fx.BoxEmitterShape(
      halfExtents: Vector3(radius * 0.85, 0.06, radius * 0.85),
    ),
    spawner: fx.Spawner(
      rate: _emberCount / _emberSeconds,
      bursts: [const fx.ParticleBurst(time: 0, count: 26)],
    ),
    looping: false,
    duration: _emberSeconds,
    lifetime: const fx.UniformFloat(1.4, 2.8),
    startSpeed: const fx.UniformFloat(0.15, 0.6),
    startSize: const fx.UniformFloat(0.16, 0.34),
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(3.4, 1.5, 0.35, 1)),
        fx.ColorStop(1, Vector4(2.0, 0.6, 0.10, 1)),
      ]),
    ),
    modules: [
      // Blackbody cooling, and out before it lands.
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            fx.ColorStop(0, Vector4(3.4, 1.6, 0.40, 0)),
            fx.ColorStop(0.08, Vector4(3.4, 1.6, 0.40, 1)),
            fx.ColorStop(0.55, Vector4(2.8, 1.0, 0.18, 0.9)),
            fx.ColorStop(1, Vector4(1.2, 0.25, 0.03, 0)),
          ]),
        ),
      ),
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 1, to: 0.35)),
      ),
      fx.TurbulenceModule(
        strength: 0.7,
        frequency: 1.4,
        scroll: Vector3(windDirection.x * 0.8, 0.15, windDirection.y * 0.8),
        seed: 91,
      ),
      fx.LinearDragModule(1.5),
    ],
    // Drifts on the wind and settles; the burnt patch is where they live.
    gravity: Vector3(windDirection.x * 0.18, -0.05, windDirection.y * 0.18),
    seed: 91,
  );

  final node = Node(localTransform: Matrix4.translation(center))
    ..frustumCulled = false
    ..addComponent(
      fx.ParticleEmitterComponent(
          system: system,
          material: softAdditiveSprite(),
        )
        ..facing = BillboardFacing.velocityStretched
        ..velocityStretch = 0.05,
    );
  world.spawn([NodeRef(node), DespawnAfter(_emberSeconds + 2.4)]);
}
