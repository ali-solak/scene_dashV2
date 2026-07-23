/// The lava pit's body: a crust on a ground disc, with globs of molten
/// rock bubbling up out of it and falling back in.
///
/// Split from the skills feature because emitters and material
/// parameters are GPU-side; the pit's damage logic stays testable
/// headless. The crust falls back to a generated lava texture when the
/// `.fmat` is unavailable: the pit is a damage zone, and a zone you
/// cannot see is worse than an ugly one.
library;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Vector2, Vector3, Vector4;

import '../skills/skills.dart' show lavaPitLift, lavaPitRadius, lavaPitSeconds;
import 'lava_texture.dart';
import 'particle_texture.dart';
import 'particles.dart' as fx;

/// Few and fat: a pool bubbles in distinct globs, and a dense stack of
/// additive blobs is how a lava pit turns into a white smear.
const int _globCount = 26;

/// The one-shot when the pit opens. Denser than the idle bubbling: this
/// is the ground breaking, and it only happens once.
const int _eruptionCount = 70;
const double _eruptionLifetime = 2.2;

/// Builds one pit node: the crust disc, plus the globs bubbling in it.
/// [center] is the pit's world position on the ground plane; the crust
/// shades from world coordinates, so it needs to know where it is.
Node buildLavaPitNode({
  required PreprocessedMaterial? material,
  required Vector2 center,
}) {
  final crust =
      Node(
          name: 'lava-crust',
          localTransform: Matrix4.translation(Vector3(0, lavaPitLift, 0)),
        )
        ..mesh = Mesh(
          DiscGeometry(radius: lavaPitRadius, segments: 48),
          material ?? _fallbackCrust(),
        );

  // The crust shades from world position, so it has to be told where the
  // pit is. Safe to set on the shared material instance: the lava
  // cooldown is longer than a pit's lifetime, so two pits never coexist.
  if (material != null) {
    material.parameters
      ..setFloat('radius', lavaPitRadius)
      ..setVec2('center', center);
  }

  final node =
      Node(
          name: 'lava-pit',
          localTransform: Matrix4.translation(Vector3(center.x, 0, center.y)),
        )
        ..frustumCulled = false
        ..add(crust)
        ..addComponent(_globs());
  return node;
}

/// Sets the pit's clock on its crust. A no-op on the generated fallback
/// (no parameters to drive); the pit still reads as alive there through
/// the globs.
void setLavaPitHeat(Node node, {required double time, required double heat}) {
  final material = node
      .getChildByName('lava-crust')
      ?.mesh
      ?.primitives
      .first
      .material;
  if (material is! PreprocessedMaterial) return; // the PBR fallback
  material.parameters
    ..setFloat('time', time)
    ..setFloat('heat', heat);
}

/// Globs: fat blobs of molten rock that swell up out of the pool, hang,
/// and fall back into it. The pit is a liquid, and a liquid bubbles;
/// embers drifting off the top would read as a campfire instead.
fx.ParticleEmitterComponent _globs() {
  final system = fx.ParticleSystem(
    maxParticles: _globCount,
    // A cone emits about +Y from a disc in the XZ plane, so with no
    // rotation this is exactly "bubbles rising from anywhere in the
    // pool". The narrow angle keeps them going up rather than spraying.
    shape: fx.ConeShape(angle: 0.3, radius: lavaPitRadius * 0.82),
    spawner: fx.Spawner(rate: _globCount / 1.7),
    duration: lavaPitSeconds,
    // Long enough to complete the arc: at this speed against the gravity
    // below, a glob rises for roughly half its life and falls for the
    // rest, which is the up-and-down the pool needs.
    lifetime: const fx.UniformFloat(0.9, 1.7),
    startSpeed: const fx.UniformFloat(1.6, 3.4),
    // Fat. These are globs of molten rock, not sparks.
    startSize: const fx.UniformFloat(0.3, 0.85),
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(1.0, 0.34, 0.04, 1)),
        fx.ColorStop(1, Vector4(0.8, 0.16, 0.02, 1)),
      ]),
    ),
    modules: [
      // Swells as it clears the surface, then necks down as it falls
      // back: a bubble rising and collapsing.
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 0.7, to: 1.25)),
      ),
      // ColorOverLifeModule replaces the colour, so the molten gradient
      // lives here. Every value at or under 1: over-bright colours turn
      // into bloom, and bloom dissolves a glob's edge into its neighbour.
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            fx.ColorStop(0, Vector4(1.00, 0.42, 0.06, 0.0)),
            fx.ColorStop(0.12, Vector4(1.00, 0.36, 0.04, 1.0)),
            fx.ColorStop(0.7, Vector4(0.82, 0.17, 0.02, 1.0)),
            // Cools and sinks back in.
            fx.ColorStop(1, Vector4(0.34, 0.05, 0.01, 0)),
          ]),
        ),
      ),
    ],
    // Real gravity, so what goes up comes back down into the pool. No
    // drag: a drag term flattens the arc into a hover.
    gravity: Vector3(0, -6.5, 0),
    seed: 71,
  );
  return fx.ParticleEmitterComponent(
    system: system,
    // Crisp and alpha-blended: globs occlude each other and the crust,
    // keeping their outlines; additive soft dots summed into one glow.
    material: crispAlphaSprite(),
  );
}

/// The pit arriving: a burst of molten rock thrown up and outward as the
/// ground splits, on its own short-lived entity. Without it the pit just
/// appears, like a decal switching on. Pure theater; the damage starts
/// on the pit's own tick.
void spawnLavaEruption(World world, Vector3 position) {
  if (!world.hasResource<Scene>()) return;
  final system = fx.ParticleSystem(
    maxParticles: _eruptionCount,
    // Wider and flatter than the pit's idle bubbling: the ground is
    // breaking open, so debris goes out as well as up.
    shape: fx.ConeShape(angle: 0.85, radius: lavaPitRadius * 0.55),
    spawner: fx.Spawner(
      bursts: [fx.ParticleBurst(time: 0, count: _eruptionCount)],
    ),
    looping: false,
    duration: 0.1,
    lifetime: const fx.UniformFloat(0.7, 1.5),
    startSpeed: const fx.UniformFloat(4.0, 10.0),
    startSize: const fx.UniformFloat(0.22, 0.7),
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(1.0, 0.45, 0.06, 1)),
        fx.ColorStop(1, Vector4(0.8, 0.18, 0.02, 1)),
      ]),
    ),
    modules: [
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 1.0, to: 0.4)),
      ),
      // Same rule as the globs: at or under 1, or the burst blooms into a
      // flash instead of reading as thrown rock.
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            fx.ColorStop(0, Vector4(1.00, 0.55, 0.12, 1.0)),
            fx.ColorStop(0.55, Vector4(0.95, 0.25, 0.03, 1.0)),
            fx.ColorStop(1, Vector4(0.30, 0.04, 0.01, 0)),
          ]),
        ),
      ),
    ],
    // Thrown debris falls back to earth.
    gravity: Vector3(0, -11, 0),
    seed: 73,
  );

  final node = Node(localTransform: Matrix4.translation(position))
    ..frustumCulled = false
    ..addComponent(
      fx.ParticleEmitterComponent(system: system, material: crispAlphaSprite()),
    );
  world.spawn([SceneNode(node), DespawnAfter(_eruptionLifetime)]);
}

/// When the `.fmat` is unavailable: a generated crust texture rather
/// than a flat fill. Static where the authored one flows, but
/// unmistakably lava; the globs supply the movement.
Material _fallbackCrust() {
  return UnlitMaterial(colorTexture: lavaCrustTexture())
    // Above 1 so the channels bloom a little against the dark grass.
    ..baseColorFactor = Vector4(1.35, 1.35, 1.35, 1);
}
