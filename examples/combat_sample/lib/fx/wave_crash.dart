/// A wave breaking against the cliff: fine spray thrown up the rock face, a
/// slower foam boiling at its foot, and a soft mist hanging after. Tinted
/// off the sea — pale blue-white sprinkles that glint (additive), white foam
/// and haze that block light and linger (alpha).
///
/// Each break varies: `intensity` scales how much it throws and how high,
/// and `seed` re-rolls the spread, so no two crashes read the same. A no-op
/// headless (`hasResource<Scene>`) like the other fx; the entity's
/// [DespawnAfter] is its whole cleanup. Sized and sped for the DISTANCE — it
/// breaks out at the cliff, ~30 units off, so a combat-scale puff would
/// vanish.
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

/// Breaks a wave at [position] (a point on the cliff face near sea level).
/// [intensity] (~0.5 small, ~1.4 big) scales the throw; [seed] re-rolls it.
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
  // A bigger break flings higher and fatter, not just more — a wide spread
  // so a small one is clearly a lap and a big one clearly a wall.
  final speedK = 0.55 + 0.75 * intensity;
  final sizeK = 0.65 + 0.5 * intensity;

  // Sprinkles: fine droplets flung up and out in a wide fan, arcing back
  // down. Additive, so they catch the sun like real spray.
  final spray = fx.ParticleSystem(
    maxParticles: sprayN,
    shape: fx.ConeShape(angle: 0.6, radius: 0.6),
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
      // ColorOverLifeModule REPLACES the colour (see impact_burst.dart), so
      // the whole sea-white gradient lives here.
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            fx.ColorStop(0, Vector4(1.1, 1.2, 1.35, 1)),
            fx.ColorStop(0.4, Vector4(0.7, 0.88, 1.0, 0.9)),
            fx.ColorStop(1, Vector4(0.4, 0.62, 0.8, 0)),
          ]),
        ),
      ),
      fx.LinearDragModule(0.4),
    ],
    gravity: Vector3(0, -12, 0),
    seed: seed,
  );

  // Foam: a fat, slow, white cloud boiling up at the base — alpha, because
  // foam blocks light, it does not glow.
  final foam = fx.ParticleSystem(
    maxParticles: foamN,
    shape: fx.ConeShape(angle: 0.85, radius: 1.0),
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

  // Mist: a wide, faint haze that hangs and drifts UP off the break after
  // the spray has fallen — the fine stuff the wind carries. Low alpha, big
  // and soft, long-lived; a veil, not a cloud.
  final mist = fx.ParticleSystem(
    maxParticles: mistN,
    shape: fx.ConeShape(angle: 1.05, radius: 1.6),
    spawner: fx.Spawner(bursts: [fx.ParticleBurst(time: 0, count: mistN)]),
    looping: false,
    duration: 0.1,
    lifetime: const fx.UniformFloat(1.6, 3.0),
    // Enough push to lift the veil UP off the break, not sit at the base.
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
      // DIM ADDITIVE (see the material below). Alpha-blended, the mist sat
      // over the bright cliff-gap sky, where source-over can only tint
      // DOWN toward the sprite's colour — so a pale veil read as a black
      // smear. Additive only ever brightens, so a soft blue-white haze
      // shows against the sky. Kept dim, and few, so it does not blow out.
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
    // Rises and hangs: mist lifts off the water rather than falling back.
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
              material: softAdditiveSprite(),
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

  world.spawn([SceneNode(node), DespawnAfter(_entityLifetime)]);
}
