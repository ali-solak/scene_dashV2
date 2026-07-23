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
    ..antiAliasingMode = AntiAliasingMode.auto;
  // renderScale / SSAO / god rays are the quality preset's to own (they
  // are what the pause menu actually trades), so boot goes through the
  // same path a menu change does rather than setting them twice.
  final boot = qualityPresets[defaultQualityLevel];
  scene.renderScale = boot.renderScale;
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
    ..enabled = boot.godRays
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
    ..enabled = boot.ambientOcclusion
    ..intensity = 1.1
    ..radius = 0.4;
}

/// Builds the clearing: the ground slab (visual + fixed Rapier collider),
/// the forest ring, and the grass field at budget. Static dressing is
/// plain scene nodes; the grass spawns as an entity so the wind system
/// reaches its material through the ECS.
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
  // Same pre-warm for the shield bubble: the first raise draws a blended
  // sphere, and compiling that pipeline mid-fight hitches the frame the
  // barrier goes up. A tiny occluded sphere on the exact material the
  // cast uses (authored `.fmat` or the unlit-blend fallback) compiles it
  // from boot instead.
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
  scene.root.add(clearing);

  // The mount adapter parents these at the scene root.
  world.spawn([const Grass(), SceneNode(_buildGrass(assets))]);
  world.spawn([const Ocean(), SceneNode(_buildOcean(assets))]);
}

/// Advances the wind clock and writes it into the grass and ocean
/// materials, resolved through their nodes so the seam shows in the
/// queries. Game-time on purpose: slow-mo slows wind and waves with
/// everything else, and a hitstop's 0.05 s pause is imperceptible.
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

/// Breaks a wave against the cliff every [waveCrashInterval]-ish seconds
/// at a random point along the treeline gap. Pure theatre, so it gates on
/// the scene, not the fight (the surf runs on the title screen too).
/// Game-time, so it pauses behind the menu with everything else.
void crashWaves(World world) {
  final clock = world.resource<WaveClock>();
  clock.until -= world.dt;
  if (clock.until > 0) return;
  clock.until = waveCrashInterval + clock.rng.nextDouble() * waveCrashJitter;
  final theta =
      cliffAzimuth + (clock.rng.nextDouble() - 0.5) * 2 * cliffHalfAngle * 0.85;
  final radius = groundIslandRadius + (clock.rng.nextDouble() - 0.5) * 2.5;
  // Every break rolls its own size and spread, so the surf never sparks
  // the same twice; a wide range so a small lap and a big wall are
  // obviously different.
  final intensity = 0.45 + clock.rng.nextDouble() * 1.25;
  spawnWaveCrash(
    world,
    Vector3(
      math.sin(theta) * radius,
      oceanLevel + waveCrashRise,
      math.cos(theta) * radius,
    ),
    intensity: intensity,
    seed: clock.rng.nextInt(1 << 30),
  );
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
  // swell can be tuned without rebuilding the shader bundle.
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
  // Deliberately NOT shadowStatic: the sway is a vertex displacement, and
  // cached shadow tiles would not follow it.
  final node = Node(name: 'grass');
  _bakeGrass(node, material, qualityPresets[defaultQualityLevel].cards);
  return node;
}

/// Bakes [cards] worth of field onto [node]. Zero is a real setting:
/// rather than feed `MeshGeometry.fromArrays` empty buffers, the node is
/// simply hidden.
void _bakeGrass(Node node, Material material, int cards) {
  if (cards <= 0) {
    node.visible = false;
    return;
  }
  final field = buildGrassField(
    cards,
    radius: grassFieldRadius,
    falloffStart: grassFalloffStart,
    seed: grassFieldSeed,
  );
  node
    ..visible = true
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

/// Applies `qualityPresets[level]` to the live scene.
///
/// The grass re-bake is the expensive half (a full vertex-buffer upload),
/// so it is skipped when the new preset asks for the same card count.
void _applyQuality(Scene scene, Node? grass, int fromLevel, int toLevel) {
  final preset = qualityPresets[toLevel];
  // Everything here is a flag flip except the render scale, which
  // reallocates the swapchain; doing that mid-session is a hard crash
  // on mobile (see `runtimeRenderScaleIsSafe`).
  if (runtimeRenderScaleIsSafe) scene.renderScale = preset.renderScale;
  scene
    ..ambientOcclusion.enabled = preset.ambientOcclusion
    ..godRays.enabled = preset.godRays;

  if (grass == null) return;
  if (qualityPresets[fromLevel].cards == preset.cards) return;
  final material = grass.mesh?.primitives.first.material;
  if (material == null) return;
  _bakeGrass(grass, material, preset.cards);
}

/// Serves the pause menu's quality choice. Polled on `update` because
/// `world.events` needs a running system; the drain is free when nobody
/// asked. Not state-gated: the change comes from the pause menu, so it
/// must land while the world is stopped.
void applyGraphicsQuality(World world) {
  var level = -1;
  for (final request in world.events<QualityRequested>()) {
    level = request.level;
  }
  if (level < 0 || level >= qualityPresets.length) return;

  final quality = world.resource<GraphicsQuality>();
  if (level == quality.level) return;

  final grass = world.query<SceneNode>(require: const [Grass]).firstOrNull;
  _applyQuality(world.resource<Scene>(), grass?.$2.node, quality.level, level);
  quality.level = level; // what the menu reads back
}
