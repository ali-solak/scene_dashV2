part of '../decor.dart';

/// Spawns the ambient leaf fall: one instanced emitter, one draw per card
/// shape, replacing the per-leaf node and its hand-rolled tumble.
void spawnLeaves(World world) {
  final scene = world.resource<Scene>();
  final field = world.resource<LeafField>();

  final system = fx.ParticleSystem(
    maxParticles: _leafCount,
    // A ceiling-height slab: leaves enter across the whole clearing rather
    // than from one point.
    shape: fx.BoxEmitterShape(
      halfExtents: Vector3(_leafFieldRadius, 0.2, _leafFieldRadius),
      // Tipped off vertical, so they drift as they fall rather than
      // dropping in parallel lines.
      direction: Vector3(
        windDirection.x * _windPush,
        -1,
        windDirection.y * _windPush,
      ),
    ),
    spawner: fx.Spawner(rate: _leafCount / _leafLifetime),
    lifetime: const fx.UniformFloat(_leafLifetime * 0.8, _leafLifetime),
    startSpeed: const fx.UniformFloat(_fallSlowest, _fallFastest),
    startSize: const fx.UniformFloat(0.8, 1.25),
    startRotation: const fx.UniformFloat(0, math.pi * 2),
    // Tumble rate, either direction.
    startAngularVelocity: const fx.UniformFloat(
      -_tumbleFastest,
      _tumbleFastest,
    ),
    gravity: Vector3(0, -_leafGravity, 0),
    modules: [
      // Air resistance: without it gravity wins and they drop like stones.
      fx.LinearDragModule(1.6),
      fx.RotationModule(),
      // Fade the spawn and the landing, so neither pops.
      fx.SizeOverLifeModule(
        fx.CurveFloat(
          fx.ParticleCurve([
            const fx.ParticleKeyframe(0, 0),
            const fx.ParticleKeyframe(0.04, 1),
            const fx.ParticleKeyframe(0.94, 1),
            const fx.ParticleKeyframe(1, 0),
          ]),
        ),
      ),
    ],
    seed: 31,
  );

  final node = Node(
    name: 'leaves',
    localTransform: Matrix4.translation(Vector3(0, _leafCeiling, 0)),
  )..frustumCulled = false;
  node.addComponent(
    fx.MeshParticleEmitterComponent(
      system: system,
      // Four cards, each with its tint baked into its vertex colours and a
      // slightly different aspect, so both colour and silhouette vary. Mesh
      // particles carry no per-particle colour, but they do carry the
      // geometry's, and every particle picks one geometry for life.
      geometries: [
        for (var i = 0; i < leafTints.length; i++)
          _leafCard(leafTints[i], _leafAspects[i]),
      ],
      material: _leafMaterial(),
      // Debris, not darts: they turn around their own axis.
      facing: fx.MeshParticleFacing.tumble,
    ),
  );
  scene.add(node);
  field.node = node;
}

/// Card aspect per tint, so the four cells differ in outline too.
const List<(double, double)> _leafAspects = [
  (1.0, 1.0),
  (0.85, 1.15),
  (1.2, 0.9),
  (0.9, 1.3),
];

/// One leaf card in [tint]. Both windings are indexed: a translucent
/// material is always back-face culled whatever `doubleSided` says, and a
/// tumbling leaf is seen from either face; without the second winding it
/// would blink out for half its turn.
MeshGeometry _leafCard((double, double, double) tint, (double, double) aspect) {
  final halfWidth = _leafSize * aspect.$1;
  final height = _leafSize * 2 * aspect.$2;
  final positions = Float32List.fromList([
    -halfWidth, -height / 2, 0, //
    halfWidth, -height / 2, 0, //
    -halfWidth, height / 2, 0, //
    halfWidth, height / 2, 0,
  ]);
  final texCoords = Float32List.fromList([
    0, 1, //
    1, 1, //
    0, 0, //
    1, 0,
  ]);
  final (r, g, b) = tint;
  final colors = Float32List.fromList([
    r, g, b, 1, //
    r, g, b, 1, //
    r, g, b, 1, //
    r, g, b, 1,
  ]);
  return MeshGeometry.fromArrays(
    positions: positions,
    texCoords: texCoords,
    colors: colors,
    indices: const [0, 1, 2, 1, 3, 2, 2, 1, 0, 2, 3, 1],
  );
}

/// One material for every card. The mask is shared; the tint rides each
/// geometry's vertex colours, which stay linear (baking them into the
/// texture sends them through the sRGB decode and they come out darker).
Material _leafMaterial() => UnlitMaterial(colorTexture: leafTexture())
  ..alphaMode = AlphaMode.blend
  ..vertexColorWeight = 1.0;
