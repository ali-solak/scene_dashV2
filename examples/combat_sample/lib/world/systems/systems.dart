part of '../world.dart';

void setupWorld(World world) {
  final scene = world.resource<Scene>();
  final sky = GradientSkySource(
    sunDirection: sunDirection,
    groundColor: skyGroundColor,
  );
  scene
    ..skybox = Skybox(sky)
    ..skyEnvironment = SkyEnvironment(sky)
    ..sunLight = SunLight(
      sky,
      intensityScale: sunIntensityScale,
      shadowMaxDistance: shadowMaxDistance,
    )
    ..toneMapping = ToneMappingMode.aces
    ..exposure = sceneExposure
    ..antiAliasingMode = AntiAliasingMode.auto
    ..renderScale = 1.0;
  scene.fog
    ..enabled = false
    ..mode = FogMode.exponential
    ..density = Fog.visibilityDensity(fogVisibilityDistance)
    ..heightFalloff = fogHeightFalloff
    ..color = fogColor
    ..skyColorInfluence = fogSkyColorInfluence
    ..maxOpacity = fogMaxOpacity
    ..cutoffDistance = fogCutoffDistance;
  scene.godRays
    ..enabled = true
    ..intensity = godRaysIntensity
    ..density = godRaysDensity
    ..maxDistance = godRaysMaxDistance;
  scene.postProcess.colorGrading
    ..enabled = true
    ..contrast = sceneContrast
    ..saturation = sceneSaturation
    ..temperature = sceneColorTemperature;
  scene.postProcess.vignette
    ..enabled = true
    ..intensity = sceneVignetteIntensity
    ..radius = sceneVignetteRadius
    ..smoothness = sceneVignetteSmoothness;
  scene.ambientOcclusion
    ..enabled = true
    ..intensity = 1.1
    ..radius = 0.4;
}

/// Builds the clearing: the ground slab (visual + fixed Rapier collider),
/// the procedural LOD forest ring, and the grass field at budget. The
/// static dressing is plain scene nodes (L4 theater); the grass spawns as
/// an entity so the wind system reaches its material through the ECS. The
/// arena-bounds clamp for fighters is `data/arena.dart`, applied by the
/// Phase-2 movement systems.
void spawnClearing(World world) {
  final scene = world.resource<Scene>();
  final assets = world.resource<WorldAssets>();
  final clearing = Node(name: 'clearing');

  clearing.add(_buildGround(assets));
  _spawnForestRing(clearing);
  // Pipeline pre-warm: the dissolve material's first appearance is a mid-
  // fight death, and compiling its pipeline then hitches the frame. A tiny
  // cube buried inside the plateau body draws it (occluded) from boot, so
  // warm-up compiles it with everything else.
  final dissolve = assets.dissolveMaterial;
  if (dissolve != null) {
    clearing.add(
      Node(
        name: 'dissolve-warmup',
        localTransform: Matrix4.translation(Vector3(0, -3, 0)),
      )..mesh = Mesh(CuboidGeometry(Vector3.all(0.3)), dissolve),
    );
  }
  scene.root.add(clearing);

  // The mount adapter parents these at the scene root.
  world.spawn([const Grass(), SceneNode(_buildGrass(assets))]);
  world.spawn([const Ocean(), SceneNode(_buildOcean(assets))]);
}

/// Advances the wind clock with game time and writes it into the grass
/// and ocean entities' materials — resolved through their nodes, so the
/// seam is visible in the queries, not hidden in a shared mutable
/// resource. Game-time (not wall-time) on purpose: slow-mo slows wind and
/// waves with everything else, and a hitstop's 0.05 s pause is
/// imperceptible.
void updateWindMaterials(World world) {
  final wind = world.resource<GrassWind>()..time += world.dt;
  final windState = world.resource<WindState>();
  // The grass strength: the dramaturgy multiplier over the base sway.
  final grassStrength = grassWindStrength * windState.strength;

  void drive(SceneNode ref, {double? strength}) {
    final material = ref.node.mesh?.primitives.first.material;
    if (material is PreprocessedMaterial) {
      material.parameters.setFloat('time', wind.time);
      if (strength != null) {
        material.parameters.setFloat('wind_strength', strength);
      }
    }
  }

  world.query<SceneNode>(require: const [Grass]).each((entity, ref) {
    drive(ref, strength: grassStrength);
  });
  world.query<SceneNode>(require: const [Ocean]).each((entity, ref) {
    drive(ref); // the ocean has no wind_strength parameter
  });
}

/// The forest as primitives: an evenly-spaced jittered pine ring with rocks
/// and bushes scattered up to the treeline, every archetype a [LodComponent]
/// (see `vfx/forest.dart`). Placement comes from the pure [layoutClearing].
void _spawnForestRing(Node clearing) {
  final kit = ForestKit.build();
  for (final placement in layoutClearing()) {
    final node = switch (placement.kind) {
      PropKind.tree => kit.tree(placement.variantRoll),
      PropKind.rock => kit.rock(placement.variantRoll),
      PropKind.bush => kit.bush(placement.variantRoll),
    };
    node.localTransform = Matrix4.compose(
      Vector3(placement.x, 0, placement.z),
      Quaternion.axisAngle(Vector3(0, 1, 0), placement.yaw),
      Vector3.all(placement.scale),
    );
    clearing.add(node);
  }
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
        ..shadowStatic = true;

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
    ..addComponent(RapierRigidBody(type: BodyType.fixed))
    ..addComponent(
      RapierCollider(
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
  // Driven from Dart rather than left on the `.fmat` defaults, so the
  // swell can be tuned without rebuilding the shader bundle — and so it
  // still has SOME value if the authored material never loads.
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

Texture2D? _bladeTexture;

Node _buildGrass(WorldAssets assets) {
  final grass = assets.grassMaterial;
  final Material material;
  if (grass != null) {
    _bladeTexture ??= Texture2D.fromPixels(bladePixels(64), 64, 64);
    grass.parameters
      ..setTexture('blade_texture', _bladeTexture!.gpuTexture)
      ..setVec2('wind_dir', windDirection.normalized())
      ..setFloat('wind_strength', grassWindStrength)
      ..setFloat('sway_scale', grassSwayScale);
    material = grass;
  } else {
    material = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(0.35, 0.5, 0.2, 1)
      ..roughnessFactor = 1;
  }
  final field = buildGrassField(
    grassCardCount,
    radius: grassFieldRadius,
    falloffStart: grassFalloffStart,
    seed: grassFieldSeed,
  );
  // Deliberately NOT shadowStatic: the sway is a vertex displacement, and
  // cached shadow tiles would not follow it.
  return Node(name: 'grass')
    ..mesh = Mesh(
      MeshGeometry.fromArrays(
        positions: field.positions,
        normals: field.normals,
        texCoords: field.texCoords,
        colors: field.colors,
        indices: field.indices,
      ),
      material,
    );
}
