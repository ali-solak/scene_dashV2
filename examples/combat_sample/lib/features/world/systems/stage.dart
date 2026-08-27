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
      reads: const {Grass, NodeRef},
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
      shadowFilter: qualityPresets[defaultQualityLevel].shadowFilter,
      contactShadows: qualityPresets[defaultQualityLevel].contactShadows,
      angularRadius: sunAngularRadius,
    )
    ..toneMapping = sceneToneMapping
    ..exposure = sceneExposure
    ..antiAliasingMode = qualityPresets[defaultQualityLevel].antiAliasing;
  final boot = qualityPresets[defaultQualityLevel];
  // SunLight.resolve rewrites the managed light every frame from its own
  // fields, and it carries neither of these, so they stay put once set.
  scene.sunLight!.light
    ..firstCascadeFarBound = shadowFirstCascadeFarBound
    ..cascadeOverlap = boot.cascadeOverlap;
  setSoftParticles(boot.softParticles);
  // Baked here rather than on the first gush: it is ~100k pixels of noise,
  // and behind the loading screen nobody feels it.
  flameAtlasSprite();
  // Metered on the GPU over the base exposure. Partial strength: the
  // clearing is meant to stay brighter than the treeline.
  scene.autoExposure
    ..enabled = boot.autoExposure
    ..strength = autoExposureStrength
    ..compensation = autoExposureCompensation;
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
    ..intensity = 0.55 // 0.21 folded the estimator's 2x
    ..radius = 0.4;

  scene.root.add(
    Node(
        name: 'irradiance-volume',
        localTransform: Matrix4.translation(
          Vector3(0, giVolumeCenterHeight, 0),
        ),
      )
      ..addComponent(
        IrradianceVolumeComponent(
          extents: giVolumeExtents,
          resolution: giResolution,
        ),
      ),
  );
  scene.globalIllumination
    ..enabled = boot.globalIllumination
    ..volumeMode = IrradianceVolumeMode.component
    ..intensity = giIntensity;
}

/// Applies requested quality settings.
void applyGraphicsQuality(World world) {
  var level = -1;
  for (final request in world.events<QualityRequested>()) {
    level = request.level;
  }
  if (level < 0 || level >= qualityPresets.length) return;

  final quality = world.resource<GraphicsQuality>();
  if (level == quality.level) return;

  final grass = world.query<NodeRef>(require: const [Grass]).firstOrNull;
  _applyQuality(
    world.resource<Scene>(),
    grass?.$2.node,
    world.hasResource<WorldAssets>()
        ? world.resource<WorldAssets>().grassMaterial
        : null,
    quality.level,
    level,
  );
  quality.level = level; // what the menu reads back
}

/// Applies `qualityPresets[level]` to the live scene.
///
/// The grass re-bake is the expensive half (a full vertex-buffer upload),
/// so it is skipped when the new preset asks for the same blade count.
void _applyQuality(
  Scene scene,
  Node? grass,
  Material? grassMaterial,
  int fromLevel,
  int toLevel,
) {
  final preset = qualityPresets[toLevel];
  // Everything here is a flag flip except the render scale, which
  // reallocates the swapchain; doing that mid-session is a hard crash
  // on mobile (see `runtimeRenderScaleIsSafe`).
  if (runtimeRenderScaleIsSafe) scene.renderScale = preset.renderScale;
  setSoftParticles(preset.softParticles);
  scene
    ..ambientOcclusion.enabled = preset.ambientOcclusion
    ..godRays.enabled = preset.godRays
    ..autoExposure.enabled = preset.autoExposure
    ..antiAliasingMode = preset.antiAliasing;
  if (scene.globalIllumination.enabled != preset.globalIllumination) {
    scene.globalIllumination.enabled = preset.globalIllumination;
    // Switching back on, the field still holds what it accumulated before.
    if (preset.globalIllumination) scene.invalidateGlobalIllumination();
  }
  scene.sunLight
    ?..shadowFilter = preset.shadowFilter
    ..contactShadows = preset.contactShadows
    ..light.cascadeOverlap = preset.cascadeOverlap;

  if (grass == null || grassMaterial == null) return;
  if (qualityPresets[fromLevel].blades == preset.blades) return;
  _bakeGrass(
    grass,
    grassMaterial,
    preset.blades,
    widthScale: preset.bladeWidthScale,
  );
}
