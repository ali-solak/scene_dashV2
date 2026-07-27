library;

import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Quaternion, Vector3, Vector4;

import '../features/skills/skills.dart' show fireGushHalfArc, fireGushRange;
import 'particle_texture.dart';
import 'particles.dart' as fx;

// Puffs, not sparks: enough overlap to read as a rolling mass of fire,
// few enough that individual puffs stay visible at combat distance.
const int _flameCount = 120;

/// How long the flame keeps pouring. The damage is instant (one cone
/// check on the cast), so this is pure theater: long enough to read as
/// a gush, short enough that it never lies about where the damage was.
const double _gushSeconds = 0.55;
const double _entityLifetime = 2.4;

/// Spawns the cone at [position], pointing along [facing] (the yaw the
/// player's model faces).
void spawnFireGush(World world, Vector3 position, double facing) {
  if (!world.hasResource<Scene>()) return;
  final system = fx.ParticleSystem(
    maxParticles: _flameCount,
    // Match the damage cone.
    shape: fx.ConeEmitterShape(angle: fireGushHalfArc, radius: 0.25),
    spawner: fx.Spawner(rate: _flameCount / _gushSeconds),
    looping: false,
    duration: _gushSeconds,
    // Cross the damage range.
    lifetime: const fx.UniformFloat(0.5, 0.85),
    // Slow: fire rolls out of the hand, it is not shot out of it.
    startSpeed: fx.UniformFloat(fireGushRange * 0.55, fireGushRange * 1.05),
    // Big soft bodies: the puff itself.
    startSize: const fx.UniformFloat(0.7, 1.5),
    // Blue near zero and green low. Additive overlap sums channels and
    // walks up through orange to yellow to white; a red-dominant stack
    // can only ever climb to saturated orange.
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(1.05, 0.20, 0.010, 1)),
        fx.ColorStop(1, Vector4(0.75, 0.07, 0.003, 1)),
      ]),
    ),
    modules: [
      // Fixed rate, not once-over-life: these live 0.5-0.85s, and 64 cells
      // over that is ~128fps, which skips cells and strobes. The atlas is
      // built to loop, so it wraps cleanly. Random start desyncs spawns.
      const fx.FlipbookModule(
        frameCount: flameAtlasFrames,
        framesPerSecond: 28,
        randomStartFrame: true,
      ),
      // Blooms as it rolls outward, then collapses: a puff of burning
      // gas expanding and being consumed.
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 0.6, to: 1.7)),
      ),
      // This gradient carries the flame colour, not a brightness curve:
      // ColorOverLifeModule replaces the colour, and anything white-ish
      // here renders white.
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            // Flame gradient.
            fx.ColorStop(0, Vector4(1.00, 0.62, 0.14, 1.0)),
            fx.ColorStop(0.3, Vector4(0.95, 0.16, 0.02, 1.0)),
            fx.ColorStop(0.7, Vector4(0.55, 0.05, 0.01, 0.85)),
            // Smoke tail.
            fx.ColorStop(1, Vector4(0.16, 0.13, 0.12, 0)),
          ]),
        ),
      ),
      // Slow the flame front.
      fx.LinearDragModule(1.9),
    ],
    // Hot gas rises, and it keeps the cone up off the grass.
    gravity: Vector3(0, 2.4, 0),
    seed: 83,
  );

  final node =
      Node(
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
              material: flameAtlasSprite(),
            )
            // Stretch along travel.
            ..facing = BillboardFacing.velocityStretched
            // Flame tongue stretch.
            ..velocityStretch = 0.3
            ..flipbookColumns = flameAtlasColumns
            ..flipbookRows = flameAtlasRows
            // Crossfade: 64 cells over a 0.5s life is far under one cell
            // per frame, so unblended steps would read as a stutter.
            ..flipbookBlend = true,
        );

  world.spawn([NodeRef(node), DespawnAfter(_entityLifetime)]);
}
