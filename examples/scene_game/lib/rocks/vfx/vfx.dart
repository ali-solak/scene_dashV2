part of '../rocks.dart';

// FlameTrailShape draws its per-particle rock pick from salt 29 — disjoint
// from the 20..23 range the wrapped ConeShape uses, per the EmitterShape
// contract.
const int _rockPickSalt = 29;

/// Spawns each ember on one of the current flaming rocks, in world space.
///
/// Upstream particles simulate in the *emitter node's local space*, so the
/// one shared emitter node is parked at the scene root at identity and
/// never moves. Parenting an emitter to a rock — or translating a node to
/// follow one — drags every live ember along with the rock, which is why
/// the trails were invisible: the whole puff rode inside the rock. Rock
/// positions enter here instead, at spawn time only: a new ember is born
/// on a rock, old embers stay where that rock left them, and the gap the
/// rock opens up is the trail.
final class FlameTrailShape extends fx.EmitterShape {
  final fx.ConeShape _cone = fx.ConeShape(
    angle: 0.5,
    radius: rockRadius * 0.35,
  );

  /// Flat xyz triples of the flaming rocks' world positions, rewritten by
  /// `updateFlameTrails` every frame.
  final List<double> origins = <double>[];

  @override
  void sample(fx.ParticleStorage storage, int index) {
    final count = origins.length ~/ 3;
    if (count == 0) return; // Unreachable: rate is 0 with no flaming rocks.
    _cone.sample(storage, index);
    var pick = (storage.randomFor(index, _rockPickSalt) * count).floor();
    if (pick >= count) pick = count - 1; // randomFor may return exactly 1.0.
    final o = pick * 3;
    storage.posX[index] += origins[o];
    storage.posY[index] += origins[o + 1];
    storage.posZ[index] += origins[o + 2];
  }
}

/// Startup (scene-gated): build the single shared flame-trail emitter at
/// the scene root and hand its steering points to the [FlameTrails]
/// resource. One emitter serves every flaming rock — `updateFlameTrails`
/// feeds it the rock positions and scales the spawn rate with the rock
/// count; there is nothing to attach, detach, or tear down per rock.
///
/// The emitter advances with the scene tick, so trails freeze under
/// hitstop like everything else; the fixed [rockTrailSeed] keeps replays
/// visually identical.
void spawnFlameTrailEmitter(World world) {
  final trails = world.resource<FlameTrails>();
  final shape = FlameTrailShape();
  final spawner = fx.Spawner(rate: 0);
  final system = fx.ParticleSystem(
    maxParticles: rockTrailMaxParticles,
    shape: shape,
    spawner: spawner,
    lifetime: const fx.UniformFloat(0.45, 0.85),
    startSpeed: const fx.UniformFloat(1.0, 2.2),
    // Big enough to overlap along the rock's ember spacing so the trail
    // reads as a continuous flame tongue, but kept restrained — crisp
    // embers, not billowing blobs.
    startSize: fx.UniformFloat(rockRadius * 0.38, rockRadius * 0.6),
    // Random facing plus a slow tumble so the wisp texture reads different
    // on every ember instead of stamping one silhouette.
    startRotation: const fx.UniformFloat(0, math.pi * 2),
    startAngularVelocity: const fx.UniformFloat(-2.5, 2.5),
    // The flame colors live in the wisp texture; the per-instance color is
    // a heat multiplier, cooling from slightly-hot toward dark red before
    // the ember fades out. Kept near 1.0 — the sprite composites source-
    // over (see `fireSprite`), so big multipliers would just clip white.
    startColor: fx.GradientColor(
      fx.ColorGradient([
        fx.ColorStop(0, Vector4(1.25, 1.2, 1.1, 1)),
        fx.ColorStop(1, Vector4(1.1, 1.0, 0.9, 1)),
      ]),
    ),
    modules: [
      // Embers shrink and cool to nothing instead of popping out.
      fx.SizeOverLifeModule(
        fx.CurveFloat(fx.ParticleCurve.linear(from: 1, to: 0.3)),
      ),
      fx.ColorOverLifeModule(
        fx.GradientColor(
          fx.ColorGradient([
            fx.ColorStop(0, Vector4(1.25, 1.2, 1.1, 1.0)),
            fx.ColorStop(0.5, Vector4(1.05, 0.62, 0.3, 0.9)),
            fx.ColorStop(0.85, Vector4(0.6, 0.18, 0.07, 0.35)),
            fx.ColorStop(1, Vector4(0.45, 0.12, 0.05, 0)),
          ]),
        ),
      ),
      fx.LinearDragModule(1.2),
    ],
    gravity: Vector3(0, 2.4, 0), // hot embers drift up
    seed: rockTrailSeed,
  );
  // Noise-eroded flame wisps, not plain glowing dots.
  final emitter = fx.ParticleEmitterComponent(
    system: system,
    material: fireSprite(),
  );
  final node = Node()
    ..frustumCulled = false
    ..addComponent(emitter);
  world.resource<Scene>().root.add(node);
  trails
    ..node = node
    ..shape = shape
    ..spawner = spawner;
}
