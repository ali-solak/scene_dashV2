/// Cliff wave effect.
library;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import 'particle_texture.dart';
import 'particles.dart' as fx;

const int _sprayCount = 140;
const int _foamCount = 56;
const int _mistCount = 40;
const double _entityLifetime = 3.6;

/// Breaks a wave at [position].
/// Spawns a wave crash with the given [intensity] and [seed].
void spawnWaveCrash(
  World world,
  Vector3 position, {
  double intensity = 1,
  int seed = 101,
}) {
  if (!world.hasResource<Scene>()) return;

  final sprayN = (_sprayCount * intensity).round().clamp(8, _sprayCount * 2);
  final foamN = (_foamCount * intensity).round().clamp(4, _foamCount * 2);
  final mistN = (_mistCount * intensity).round().clamp(4, _mistCount * 2);
  // A bigger break flings higher and fatter, not just more: a small one
  // is clearly a lap and a big one clearly a wall.
  final speedK = 0.55 + 0.75 * intensity;
  final sizeK = 0.65 + 0.5 * intensity;

  // Sprinkles: fine droplets flung up and out in a wide fan, arcing back
  // down. Additive, so they catch the sun like real spray.
  final spray = fx.ParticleSystem(
    maxParticles: sprayN,
    shape: fx.ConeEmitterShape(angle: 0.6, radius: 0.6),
    spawner: fx.Spawner(bursts: [fx.ParticleBurst(time: 0, count: sprayN)]),
    looping: false,
    duration: 0.1,
    lifetime: const fx.UniformFloat(1.0, 2.2),
    startSpeed: fx.UniformFloat(14 * speedK, 26 * speedK),
    startSize: fx.UniformFloat(0.25 * sizeK, 0.6 * sizeK),
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(0.9, 0.97, 1.0, 1)),
        fx.ColorStop(1, Vector4(0.55, 0.78, 0.92, 1)),
      ]),
    ),
    modules: [
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 1, to: 0.3)),
      ),
      // Sea spray gradient.
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            fx.ColorStop(0, Vector4(0.85, 0.95, 1.1, 1)),
            fx.ColorStop(0.4, Vector4(0.6, 0.78, 0.95, 0.85)),
            fx.ColorStop(1, Vector4(0.34, 0.55, 0.75, 0)),
          ]),
        ),
      ),
      fx.LinearDragModule(0.4),
    ],
    gravity: Vector3(0, -12, 0),
    seed: seed,
  );

  // Foam.
  final foam = fx.ParticleSystem(
    maxParticles: foamN,
    shape: fx.ConeEmitterShape(angle: 0.85, radius: 1.0),
    spawner: fx.Spawner(bursts: [fx.ParticleBurst(time: 0, count: foamN)]),
    looping: false,
    duration: 0.1,
    lifetime: const fx.UniformFloat(1.0, 1.9),
    startSpeed: fx.UniformFloat(3 * speedK, 8 * speedK),
    startSize: fx.UniformFloat(1.1 * sizeK, 2.8 * sizeK),
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(0.95, 0.98, 1.0, 1)),
        fx.ColorStop(1, Vector4(0.82, 0.9, 0.95, 1)),
      ]),
    ),
    modules: [
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 0.7, to: 1.6)),
      ),
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            fx.ColorStop(0, Vector4(0.95, 0.98, 1.0, 0)),
            fx.ColorStop(0.15, Vector4(0.92, 0.96, 1.0, 0.92)),
            fx.ColorStop(1, Vector4(0.72, 0.84, 0.9, 0)),
          ]),
        ),
      ),
      fx.LinearDragModule(2.2),
    ],
    gravity: Vector3(0, -4, 0),
    seed: seed + 1,
  );

  // Mist.
  final mist = fx.ParticleSystem(
    maxParticles: mistN,
    shape: fx.ConeEmitterShape(angle: 1.05, radius: 1.6),
    spawner: fx.Spawner(bursts: [fx.ParticleBurst(time: 0, count: mistN)]),
    looping: false,
    duration: 0.1,
    lifetime: const fx.UniformFloat(1.6, 3.0),
    // Lift mist from the break.
    startSpeed: const fx.UniformFloat(2.5, 6.0),
    startSize: fx.UniformFloat(2.2 * sizeK, 5.0 * sizeK),
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(0.3, 0.36, 0.42, 1)),
        fx.ColorStop(1, Vector4(0.2, 0.26, 0.32, 1)),
      ]),
    ),
    modules: [
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 0.8, to: 2.2)),
      ),
      // Dim additive mist.
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            fx.ColorStop(0, Vector4(0.05, 0.07, 0.1, 1)),
            fx.ColorStop(0.4, Vector4(0.19, 0.24, 0.31, 1)),
            fx.ColorStop(1, Vector4(0, 0, 0, 0)),
          ]),
        ),
      ),
      fx.LinearDragModule(1.1),
    ],
    // Rising mist.
    gravity: Vector3(0, 1.8, 0),
    seed: seed + 2,
  );

  final node = Node(localTransform: Matrix4.translation(position))
    ..frustumCulled = false
    ..add(
      Node()
        ..frustumCulled = false
        ..addComponent(
          fx.ParticleEmitterComponent(
              system: spray,
              // Droplets, not sparks: the soft dot's hot core reads as a
              // spray of hard bright points at this distance.
              material: dropletAdditiveSprite(),
            )
            ..facing = BillboardFacing.velocityStretched
            ..velocityStretch = 0.08,
        ),
    )
    ..add(
      Node()
        ..frustumCulled = false
        ..addComponent(
          fx.ParticleEmitterComponent(
            system: foam,
            material: puffAlphaSprite(),
          ),
        ),
    )
    ..add(
      Node()
        ..frustumCulled = false
        ..addComponent(
          fx.ParticleEmitterComponent(
            system: mist,
            material: softAdditiveSprite(),
          ),
        ),
    );

  world.spawn([NodeRef(node), DespawnAfter(_entityLifetime)]);
}
