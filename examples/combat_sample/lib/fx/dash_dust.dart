/// The dash's mud: a low scuff of earth kicked up where the roll pushes
/// off, thrown BACKWARD along the dodge so the ground reads as being
/// shoved against.
///
/// A no-op headless, like the other fx.
library;

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Quaternion, Vector3, Vector4;

import 'particle_texture.dart';
import 'particles.dart' as fx;

const int _clodCount = 90;
const double _entityLifetime = 1.6;

/// Spawns the scuff at [position] (the player's feet), kicked away along
/// [heading] — the direction the dash is travelling, so the dirt flies
/// out behind it.
void spawnDashDust(World world, Vector3 position, Vector3 heading) {
  if (!world.hasResource<Scene>()) return;
  final system = fx.ParticleSystem(
    maxParticles: _clodCount,
    // A shallow cone: the spray fans out low rather than fountaining.
    shape: const fx.ConeShape(angle: 0.85, radius: 0.45),
    spawner: fx.Spawner(
      bursts: [fx.ParticleBurst(time: 0, count: _clodCount)],
    ),
    looping: false,
    duration: 0.1,
    lifetime: const fx.UniformFloat(0.45, 1.0),
    startSpeed: const fx.UniformFloat(3.5, 9.0),
    startSize: const fx.UniformFloat(0.2, 0.55),
    // Wet forest earth, not dust: dark and brown, so it reads against
    // the grass instead of glowing over it.
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(0.26, 0.19, 0.11, 1)),
        fx.ColorStop(1, Vector4(0.15, 0.12, 0.08, 1)),
      ]),
    ),
    modules: [
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 1, to: 0.35)),
      ),
    // NOTE: ColorOverLifeModule REPLACES the particle colour outright —
    // it does not modulate `startColor`. A white curve here renders white
    // no matter what `startColor` says, which is why every effect in this
    // directory once looked like grey mist. Carry the real colour here.
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            fx.ColorStop(0, Vector4(0.28, 0.21, 0.12, 0.95)),
            fx.ColorStop(1, Vector4(0.14, 0.11, 0.07, 0)),
          ]),
        ),
      ),
      fx.LinearDragModule(2.2),
    ],
    // Real weight: clods of earth arc and fall back down.
    gravity: Vector3(0, -14, 0),
    seed: 101,
  );

  // Point the cone back along the dash and tip it up off the ground, so
  // the spray trails the dodge.
  final yaw = math.atan2(-heading.x, -heading.z);
  final node = Node(
    localTransform: Matrix4.compose(
      Vector3(position.x, position.y + 0.15, position.z),
      Quaternion.axisAngle(Vector3(0, 1, 0), yaw) *
          Quaternion.axisAngle(Vector3(1, 0, 0), math.pi * 0.34),
      Vector3.all(1),
    ),
  )
    ..frustumCulled = false
    ..addComponent(
      fx.ParticleEmitterComponent(
        system: system,
        // The soft dot, NOT additive fire: dirt occludes, it does not glow.
        material: softAlphaSprite(),
      ),
    );

  world.spawn([SceneNode(node), DespawnAfter(_entityLifetime)]);
}
