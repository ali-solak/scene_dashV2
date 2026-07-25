part of '../world.dart';

/// The scene look: sky, sun, fog, god rays, tone mapping, and the
/// quality preset the pause menu trades against.
void installStageLook(GameBuilder game) {
  game
    ..world.insert(GraphicsQuality(defaultQualityLevel))
    ..addSystem(
      Schedules.startup,
      setupWorld,
      reads: const {},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      applyGraphicsQuality,
      reads: const {Grass, SceneNode},
      runIf: hasResource<Scene>(),
    );
}

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

/// Applies `qualityPresets[level]` to the live scene.
///
/// The grass re-bake is the expensive half (a full vertex-buffer upload),
/// so it is skipped when the new preset asks for the same blade count.
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
  if (qualityPresets[fromLevel].blades == preset.blades) return;
  final material = grass.mesh?.primitives.first.material;
  if (material == null) return;
  _bakeGrass(grass, material, preset.blades);
}
