/// Fire on a burning body: a small looping flame that rides the victim
/// for as long as the burn ticks.
///
/// Unlike the one-shot bursts, this one is attached to an existing node
/// rather than spawned as its own entity; the flame has to follow the
/// barbarian around, and the burn's own `removeAfter:` clock decides
/// when it stops.
library;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

import 'particle_texture.dart';
import 'particles.dart' as fx;

/// Enough to read as a body on fire at combat distance; the fix for
/// additive stacking is short-lived sparks, not fewer clouds.
const int _flameCount = 70;

/// Roughly the middle of the 2.6u body, so the fire wraps the torso
/// instead of pooling at the feet.
const double _bodyHeight = 1.3;

/// Builds the flame node to hang on a burning body. Returned rather than
/// attached so the caller owns the handle it will need to detach.
Node buildBurnFlame() {
  final system = fx.ParticleSystem(
    maxParticles: _flameCount,
    // Body-sized, so flames lick up the whole silhouette.
    shape: fx.SphereShape(radius: 0.45),
    spawner: fx.Spawner(rate: _flameCount / 0.5),
    duration: 1,
    // Short and quick: embers flicking off a burning body.
    lifetime: const fx.UniformFloat(0.3, 0.6),
    startSpeed: const fx.UniformFloat(1.4, 3.6),
    startSize: const fx.UniformFloat(0.22, 0.5),
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(1.10, 0.24, 0.02, 1)),
        fx.ColorStop(1, Vector4(0.75, 0.08, 0.005, 1)),
      ]),
    ),
    modules: [
      // Burns down to a point as it flicks upward.
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 1.2, to: 0.15)),
      ),
      // Fire colours, blue near zero; see fire_gush.dart on why a
      // white-ish curve here renders as white mist.
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            // Red-dominant, same rule as the gush: green low so the
            // stack cannot climb toward yellow and white.
            fx.ColorStop(0, Vector4(1.00, 0.42, 0.07, 1.0)),
            fx.ColorStop(0.35, Vector4(0.92, 0.15, 0.02, 1.0)),
            fx.ColorStop(1, Vector4(0.22, 0.03, 0.00, 0)),
          ]),
        ),
      ),
      fx.LinearDragModule(1.2),
    ],
    // Upward: fire rises off the body it is burning.
    gravity: Vector3(0, 4.5, 0),
    seed: 97,
  );

  return Node(
      name: 'burn-flame',
      localTransform: Matrix4.translation(Vector3(0, _bodyHeight, 0)),
    )
    ..frustumCulled = false
    ..addComponent(
      fx.ParticleEmitterComponent(system: system, material: puffAlphaSprite())
        ..facing = BillboardFacing.velocityStretched
        ..velocityStretch = 0.1,
    );
}
