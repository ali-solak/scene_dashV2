/// The fire gush's flame: a cone of burning particles thrown along the
/// player's facing.
///
/// A no-op headless (`hasResource<Scene>`), like the impact burst — the
/// skill's damage does not depend on it. The entity's [DespawnAfter] is
/// the whole cleanup.
library;

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Quaternion, Vector3, Vector4;

import '../skills/skills.dart' show fireGushHalfArc, fireGushRange;
import 'particle_texture.dart';
import 'particles.dart' as fx;

// PUFFS, not sparks. Enough overlapping bodies to read as a rolling mass
// of fire, few enough that you can still see individual puffs turning
// over inside it. The earlier spark pass went too far the other way:
// thin fast streaks are legible up close and nearly invisible at combat
// distance.
const int _flameCount = 120;

/// How long the flame keeps pouring. The damage is instant (one cone
/// check on the cast), so this is pure theater — long enough to read as
/// a gush, short enough that it never lies about where the damage was.
const double _gushSeconds = 0.55;
const double _entityLifetime = 2.4;

/// Spawns the cone at [position], pointing along [facing] (the yaw the
/// player's model faces).
void spawnFireGush(World world, Vector3 position, double facing) {
  if (!world.hasResource<Scene>()) return;
  final system = fx.ParticleSystem(
    maxParticles: _flameCount,
    // The cone the gameplay check uses, as geometry: same half-angle, so
    // the flame you see is the flame that burned.
    shape: fx.ConeShape(angle: fireGushHalfArc, radius: 0.25),
    spawner: fx.Spawner(rate: _flameCount / _gushSeconds),
    looping: false,
    duration: _gushSeconds,
    // Fast enough to cross the cone's reach inside its lifetime — the
    // flame front should arrive where the damage did.
    // Long enough for a puff to bloom, roll and burn out where you can
    // watch it.
    lifetime: const fx.UniformFloat(0.5, 0.85),
    // Slower than the spark pass: fire ROLLS out of the hand, it is not
    // shot out of it.
    startSpeed: fx.UniformFloat(fireGushRange * 0.55, fireGushRange * 1.05),
    // Big soft bodies — the puff itself.
    startSize: const fx.UniformFloat(0.7, 1.5),
    // BLUE IS THE ENEMY. Additive blending sums channels, so wherever
    // sprites overlap the strongest channel clips at 1 first and the
    // others keep climbing — red saturates, then green, and the pixel
    // walks up through orange to yellow to white. That is exactly the
    // "reddish white cloud" this used to be.
    //
    // Holding blue near zero and green low means a deep stack can only
    // ever climb to saturated orange: the dense base of the cone reads
    // white-hot because it is dense, and the thin tips stay red, which
    // is the gradient real flame has.
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(1.05, 0.20, 0.010, 1)),
        fx.ColorStop(1, Vector4(0.75, 0.07, 0.003, 1)),
      ]),
    ),
    modules: [
      // Blooms as it rolls outward, then collapses — the shape of a puff
      // of burning gas expanding and being consumed.
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 0.6, to: 1.7)),
      ),
      // This gradient carries the FLAME COLOUR, not a brightness curve.
      //
      // The previous version was near-white (1, 0.95, 0.85) on the theory
      // that it only scaled the start colour. Whether it multiplies or
      // replaces, a white-ish gradient over a white premultiplied sprite
      // under additive blending can only produce white — which is exactly
      // what it produced. Every stop here is an actual fire colour with
      // blue near zero, so there is no path to white through any of it.
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            // RED-dominant the whole way. Green is what carries a flame
            // toward yellow and then white under additive stacking, so it
            // stays low even at the hot end and drops away fast; blue is
            // effectively off throughout.
            // Under alpha blending these are the colours you actually
            // SEE — nothing sums, so they can be read straight off a
            // reference instead of being kept artificially dim.
            fx.ColorStop(0, Vector4(1.00, 0.45, 0.08, 1.0)),
            fx.ColorStop(0.3, Vector4(0.95, 0.16, 0.02, 1.0)),
            fx.ColorStop(0.7, Vector4(0.55, 0.05, 0.01, 0.85)),
            // Dies down to smoke rather than to haze.
            fx.ColorStop(1, Vector4(0.16, 0.13, 0.12, 0)),
          ]),
        ),
      ),
      // Some drag, so the puffs slow and pile up into a rolling front
      // rather than flying out like buckshot.
      fx.LinearDragModule(1.9),
    ],
    // Hot gas rises, and it keeps the cone up off the grass.
    gravity: Vector3(0, 2.4, 0),
    seed: 83,
  );

  final node = Node(
    localTransform: Matrix4.compose(
      position,
      // The cone shape emits along its local axis; yaw it onto the
      // player's facing, then tip it to point at the horizon.
      Quaternion.axisAngle(Vector3(0, 1, 0), facing) *
          Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2),
      Vector3.all(1),
    ),
  )
    ..frustumCulled = false
    ..addComponent(
      fx.ParticleEmitterComponent(
        system: system,
        // Tongues, not dots.
        material: flameAdditiveSprite(),
      )
        // Stretched along travel: round sprites read as a cloud of balls,
        // stretched ones read as tongues of flame licking outward.
        ..facing = BillboardFacing.velocityStretched
        // Hard stretch: this is what turns a dot into a dart. The higher
        // this is, the more the cone reads as spitting sparks instead of
        // exhaling smoke.
        ..velocityStretch = 0.3,
    );

  world.spawn([
    SceneNode(node),
    DespawnAfter(_entityLifetime),
  ]);
}
