part of '../world.dart';

/// Installs the clearing.
void installClearing(GameBuilder game) {
  game
    ..registerTag<Grass>()
    ..registerTag<Ocean>()
    ..addSystem(
      Schedules.startup,
      spawnClearing,
      writes: const {Grass, Ocean},
      after: const [setupWorld],
      runIf: hasResource<Scene>(),
    );
}

/// Builds the clearing.
void spawnClearing(World world) {
  final scene = world.resource<Scene>();
  final assets = world.resource<WorldAssets>();
  final clearing = Node(name: 'clearing');

  clearing.add(_buildGround(assets));
  _spawnForestRing(clearing);
  // Big wet boulders massed at the foot of the cliff in the treeline gap,
  // where the surf breaks against them.
  clearing.add(buildCliffRocks());
  // Pipeline pre-warm: the dissolve's first real draw is a mid-fight
  // death, and compiling its pipeline then hitches the frame. A tiny
  // occluded cube inside the plateau draws it from boot instead.
  final dissolve = assets.dissolveMaterial;
  if (dissolve != null) {
    clearing.add(
      Node(
        name: 'dissolve-warmup',
        localTransform: Matrix4.translation(Vector3(0, -3, 0)),
      )..mesh = Mesh(CuboidGeometry(Vector3.all(0.3)), dissolve),
    );
  }
  // Same pre-warm for the shield bubble, on the exact material the cast
  // uses, so its pipeline compiles at boot rather than mid-fight.
  clearing.add(
    Node(
        name: 'barrier-warmup',
        localTransform: Matrix4.translation(Vector3(0, -3, 0)),
      )
      ..mesh = Mesh(
        SphereGeometry(radius: 0.3, segments: 32, rings: 16),
        assets.barrierMaterial ??
            (UnlitMaterial()..alphaMode = AlphaMode.blend),
      ),
  );
  // The plateau, treeline and boulders never move, so their shadow tiles
  // are cached instead of re-rendered every frame. Skips the grass and the
  // ocean: both displace in a vertex stage.
  _markShadowStatic(clearing);
  clearing.add(buildLavaWarmup(assets.lavaMaterial));
  scene.root.add(clearing);

  // The mount adapter parents these at the scene root.
  world.spawn([const Grass(), NodeRef(_buildGrass(assets))]);
  world.spawn([const Ocean(), NodeRef(_buildOcean(assets))]);
}

void _markShadowStatic(Node node) {
  if (node.mesh != null) node.shadowStatic = true;
  for (final child in node.children) {
    _markShadowStatic(child);
  }
}

/// The forest: an evenly-spaced jittered pine ring with rocks and bushes
/// scattered up to the treeline, all statically batched into one mesh.
/// Placement comes from the pure [layoutClearing].
void _spawnForestRing(Node clearing) {
  clearing.add(buildForestBatch(layoutClearing()));
}

/// The plateau the clearing sits on: a grass-topped disc with a cliff
/// wall dropping to the sea (visible through the treeline's gap).
Node _buildGround(WorldAssets assets) {
  final top =
      Node(
          name: 'ground-top',
          localTransform: Matrix4.translation(
            Vector3(0, groundThickness / 2, 0),
          ),
        )
        ..mesh = Mesh(
          DiscGeometry(radius: groundIslandRadius, segments: 64),
          assets.groundMaterial ??
              (PhysicallyBasedMaterial()
                ..baseColorFactor = Vector4(0.12, 0.3, 0.08, 1)
                ..roughnessFactor = 1),
        )
        ..shadowStatic = true
        ..lightChannelMask = defaultLightChannels;

  final wall =
      Node(
          name: 'cliff-wall',
          localTransform: Matrix4.translation(
            Vector3(0, groundThickness / 2 - cliffHeight / 2, 0),
          ),
        )
        ..mesh = Mesh(
          CylinderGeometry(
            bottomRadius: groundIslandRadius,
            topRadius: groundIslandRadius,
            height: cliffHeight,
            radialSegments: 64,
            topCap: false,
            bottomCap: false,
          ),
          PhysicallyBasedMaterial()
            ..baseColorFactor = Vector4(0.35, 0.28, 0.2, 1)
            ..roughnessFactor = 1,
        )
        ..shadowStatic = true;

  // The collider slab sits below y = 0 so its top face is the floor the
  // fighters' grounding queries hit.
  return Node(
      name: 'ground',
      localTransform: Matrix4.translation(Vector3(0, -groundThickness / 2, 0)),
    )
    ..addComponent(RigidBody(type: BodyType.fixed))
    ..addComponent(
      Collider(
        shape: BoxShape(
          halfExtents: Vector3(
            groundIslandRadius,
            groundThickness / 2,
            groundIslandRadius,
          ),
        ),
        collisionLayer: PhysicsLayers.ground,
      ),
    )
    ..add(top)
    ..add(wall);
}

/// The sea: a tessellated grid (the wave vertex stage needs vertices) far
/// below the plateau, glossy under the low sun and the god rays.
Node _buildOcean(WorldAssets assets) {
  const segments = oceanGridSegments;
  const half = oceanHalfExtent;
  const step = 2 * half / segments;
  final positions = Float32List((segments + 1) * (segments + 1) * 3);
  final normals = Float32List(positions.length);
  var v = 0;
  for (var row = 0; row <= segments; row++) {
    for (var column = 0; column <= segments; column++) {
      positions[v * 3] = -half + column * step;
      positions[v * 3 + 2] = -half + row * step;
      normals[v * 3 + 1] = 1;
      v++;
    }
  }
  final indices = Uint32List(segments * segments * 6);
  var i = 0;
  for (var row = 0; row < segments; row++) {
    for (var column = 0; column < segments; column++) {
      final a = row * (segments + 1) + column;
      final b = a + 1;
      final c = a + segments + 1;
      final d = c + 1;
      indices[i++] = a;
      indices[i++] = d;
      indices[i++] = b;
      indices[i++] = a;
      indices[i++] = c;
      indices[i++] = d;
    }
  }
  final material =
      assets.oceanMaterial ??
      (UnlitMaterial()..baseColorFactor = Vector4(0.06, 0.2, 0.3, 1));
  // Apply ocean tuning.
  if (material is PreprocessedMaterial) {
    material.parameters
      ..setFloat('wave_height', oceanWaveHeight)
      ..setFloat('wave_scale', oceanWaveScale);
  }
  return Node(
      name: 'ocean',
      localTransform: Matrix4.translation(Vector3(0, oceanLevel, 0)),
    )
    ..mesh = Mesh(
      MeshGeometry.fromArrays(
        positions: positions,
        normals: normals,
        indices: indices,
      ),
      material,
    );
}

Node _buildGrass(WorldAssets assets) {
  final grass = assets.grassMaterial;
  final Material material;
  if (grass != null) {
    grass.parameters
      ..setVec2('wind_dir', windDirection.normalized())
      ..setFloat('wind_strength', grassWindStrength)
      ..setFloat('sway_scale', grassSwayScale);
    material = grass;
  } else {
    material = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(0.35, 0.5, 0.2, 1)
      ..roughnessFactor = 1
      ..doubleSided = true;
  }
  // Deliberately NOT shadowStatic: the sway is a vertex displacement, and
  // cached shadow tiles would not follow it.
  final node = Node(name: 'grass')..lightChannelMask = defaultLightChannels;
  _bakeGrass(
    node,
    material,
    qualityPresets[defaultQualityLevel].blades,
    widthScale: qualityPresets[defaultQualityLevel].bladeWidthScale,
  );
  return node;
}

/// Bakes [blades] onto [node] as one instanced batch.
void _bakeGrass(
  Node node,
  Material material,
  int blades, {
  required double widthScale,
}) {
  final previous = node.getChildByName(_grassBladesNode);
  if (previous != null) node.remove(previous);
  if (blades <= 0) {
    node.visible = false;
    return;
  }
  final field = buildGrassField(
    blades,
    radius: grassFieldRadius,
    falloffStart: grassFalloffStart,
    seed: grassFieldSeed,
    widthScale: widthScale,
  );
  final mesh = InstancedMesh(
    geometry: MeshGeometry.fromArrays(
      positions: Float32List.fromList(GrassField.bladePositions),
      normals: Float32List.fromList(GrassField.bladeNormals),
      indices: Uint32List.fromList(GrassField.bladeIndices),
    ),
    material: material,
  );
  // Reused; addInstance copies both.
  final transform = Matrix4.zero();
  final color = Vector4.zero();
  for (var blade = 0; blade < field.bladeCount; blade++) {
    transform.storage.setRange(
      0,
      GrassField.floatsPerTransform,
      field.transforms,
      blade * GrassField.floatsPerTransform,
    );
    final c = blade * GrassField.floatsPerColor;
    color.setValues(
      field.colors[c],
      field.colors[c + 1],
      field.colors[c + 2],
      field.colors[c + 3],
    );
    mesh.addInstance(transform, color: color);
  }
  node
    ..visible = true
    ..add(
      Node(name: _grassBladesNode)
        ..castsShadows = false
        ..addComponent(InstancedMeshComponent(mesh)),
    );
}

/// The blade batch, a child so a quality re-bake can swap it wholesale
/// (`InstancedMeshComponent.instancedMesh` is final).
const String _grassBladesNode = 'grass-blades';
