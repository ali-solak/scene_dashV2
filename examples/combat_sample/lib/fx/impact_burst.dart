/// The hit's visual punch: a spark burst at the point of contact.
///
/// A no-op headless (`hasResource<Scene>`) — emitter construction builds
/// GPU-side billboard geometry — so the hit logic that calls it stays
/// fully testable. The burst entity's [DespawnAfter] is the whole
/// cleanup: the built-in ticker despawns it once the sparks die and the
/// node (emitter included) unmounts with it.
library;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import 'particle_texture.dart';
import 'particles.dart' as fx;

// Kept modest on purpose: a burst is built PER CONNECT, and the particle
// system allocates its buffers at construction. Every particle here is
// paid for in the middle of a swing.
const int _lightCount = 20;
const int _heavyCount = 38;
const double _burstEntityLifetime = 1.2;

/// Spawns one impact burst at [position]. A heavy connect throws a bigger,
/// hotter, faster spray — the visual half of the hit's weight.
void spawnImpactBurst(World world, Vector3 position, {bool heavy = false}) {
  if (!world.hasResource<Scene>()) return;
  final count = heavy ? _heavyCount : _lightCount;
  final system = fx.ParticleSystem(
    maxParticles: count,
    // A zero-radius sphere degenerates to a point emitting uniformly in
    // every direction — a clean point burst.
    shape: const fx.SphereShape(radius: 0),
    spawner: fx.Spawner(bursts: [fx.ParticleBurst(time: 0, count: count)]),
    looping: false,
    duration: 0.1,
    lifetime: heavy
        ? const fx.UniformFloat(0.22, 0.5)
        : const fx.UniformFloat(0.14, 0.3),
    startSpeed: heavy
        ? const fx.UniformFloat(6.0, 13.0)
        : const fx.UniformFloat(3.5, 7.0),
    startSize: heavy
        ? const fx.UniformFloat(0.18, 0.38)
        : const fx.UniformFloat(0.1, 0.22),
    startColor: fx.GradientColor(
      fx.ColorGradient(
        heavy
            ? [
                fx.ColorStop(0, Vector4(1.0, 0.85, 0.45, 1)),
                fx.ColorStop(1, Vector4(1.0, 0.45, 0.12, 1)),
              ]
            : [
                fx.ColorStop(0, Vector4(1.0, 0.9, 0.7, 1)),
                fx.ColorStop(1, Vector4(1.0, 0.6, 0.3, 1)),
              ],
      ),
    ),
    modules: [
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 1, to: 0.2)),
      ),
      // NOTE: ColorOverLifeModule REPLACES the particle colour outright —
      // it does not modulate `startColor`. A white curve here renders white
      // no matter what `startColor` says, which is why every effect in this
      // directory once looked like grey mist. Carry the real colour here.
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            // Struck-steel: a yellow-hot instant, then the spark cools
            // down through orange to red and goes out.
            fx.ColorStop(0, Vector4(2.0, 1.45, 0.45, 1)),
            fx.ColorStop(0.2, Vector4(1.5, 0.65, 0.12, 1)),
            fx.ColorStop(1, Vector4(0.55, 0.12, 0.02, 0)),
          ]),
        ),
      ),
      fx.LinearDragModule(3.2),
    ],
    gravity: Vector3(0, -6, 0),
    seed: heavy ? 47 : 23,
  );
  final emitter =
      fx.ParticleEmitterComponent(
          system: system,
          material: softAdditiveSprite(),
        )
        ..facing = BillboardFacing.velocityStretched
        ..velocityStretch = 0.06;
  final node = Node(localTransform: Matrix4.translation(position))
    ..frustumCulled = false
    ..addComponent(emitter);
  world.spawn([SceneNode(node), DespawnAfter(_burstEntityLifetime)]);
}
