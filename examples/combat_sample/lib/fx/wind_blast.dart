/// The wind blast's shockwave: a ring of dust driven outward at ankle
/// height, so the skill reads as a wave LEAVING the player rather than a
/// flash on top of them.
///
/// A no-op headless, like the other fx.
library;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import '../skills/skills.dart' show windBlastRadius;
import 'particle_texture.dart';
import 'particles.dart' as fx;

const int _dustCount = 220;
const double _entityLifetime = 2.0;

/// Spawns the ring at [position] (the player's feet).
void spawnWindBlast(World world, Vector3 position) {
  if (!world.hasResource<Scene>()) return;
  final system = fx.ParticleSystem(
    maxParticles: _dustCount,
    // A zero-radius sphere emits uniformly in every direction; the drag
    // and the near-zero gravity flatten it into a ground-hugging ring.
    shape: const fx.SphereShape(radius: 0),
    spawner: fx.Spawner(
      bursts: [fx.ParticleBurst(time: 0, count: _dustCount)],
    ),
    looping: false,
    duration: 0.1,
    lifetime: const fx.UniformFloat(0.6, 1.15),
    // Sized to actually cross the blast's radius inside its lifetime, so
    // the dust front marks the edge of what got thrown.
    startSpeed: fx.UniformFloat(windBlastRadius * 0.9, windBlastRadius * 1.6),
    startSize: const fx.UniformFloat(0.6, 1.5),
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(0.85, 0.9, 0.95, 1)),
        fx.ColorStop(1, Vector4(0.6, 0.66, 0.72, 1)),
      ]),
    ),
    modules: [
      // Dust spreads as it travels and fades out at the rim.
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 0.6, to: 3.0)),
      ),
    // NOTE: ColorOverLifeModule REPLACES the particle colour outright —
    // it does not modulate `startColor`. A white curve here renders white
    // no matter what `startColor` says, which is why every effect in this
    // directory once looked like grey mist. Carry the real colour here.
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            fx.ColorStop(0, Vector4(0.62, 0.58, 0.48, 0.8)),
            fx.ColorStop(0.5, Vector4(0.48, 0.45, 0.38, 0.5)),
            fx.ColorStop(1, Vector4(0.34, 0.32, 0.28, 0)),
          ]),
        ),
      ),
      fx.LinearDragModule(2.6),
    ],
    // Barely any: the dust hangs and drifts instead of falling.
    gravity: Vector3(0, -0.6, 0),
    seed: 89,
  );

  final node = Node(
    localTransform: Matrix4.translation(
      Vector3(position.x, position.y + 0.35, position.z),
    ),
  )
    ..frustumCulled = false
    ..addComponent(
      fx.ParticleEmitterComponent(
        system: system,
        // Alpha, not additive: kicked-up earth blocks light, it does not
        // emit it. Additive dust is what "glowing white cloud" is made of.
        material: softAlphaSprite(),
      )
        // Stretched along travel, so the ring reads as a gust driving
        // outward rather than a puff sitting still.
        ..facing = BillboardFacing.velocityStretched
        ..velocityStretch = 0.05,
    );

  // No DespawnOnExit: leaving `fighting` is routine (the skill menu is a
  // state), and a pause must not wipe what is on screen. The DespawnAfter
  // bounds this entity on its own.
  world.spawn([SceneNode(node), DespawnAfter(_entityLifetime)]);
}
