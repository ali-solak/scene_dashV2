library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_scene/scene.dart'
    show AntiAliasingMode, DirectionalShadowFilter, ToneMappingMode;
import 'package:vector_math/vector_math.dart' show Vector2, Vector3;

final bool isMobile =
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

final bool heavyAtmospherics = !isMobile;

final bool runtimeRenderScaleIsSafe = !isMobile;

const double characterScale = 2.6 / 2.543;

const double characterModelYaw = math.pi;

const double propScale = 1.0;

const double arenaRadius = 14;

const double arenaBoundsRadius = arenaRadius - 0.9;

const double gravityStrength = 20;

const double groundHalfExtent = 60;

const double groundThickness = 1;

const int clearingSeed = 41;

const double treeRingInner = 20;
const double treeRingOuter = 24;
const int treeCount = 64;

const double scatterInner = arenaRadius + 1.5;
const double scatterOuter = treeRingInner + 4;
const int rockCount = 14;
const int bushCount = 26;

const int underbrushCount = 36;
const double underbrushRadius = treeRingInner - 1.5;
const double underbrushJitter = 0.9;

final double cliffAzimuth = math.atan2(sunDirection.x, sunDirection.z);
const double cliffHalfAngle = 0.6;

/// Opens short of the sun, so the orbit drifts onto it and the run starts
/// backlit.
final double titleCameraStartYaw = cliffAzimuth - 0.4;

const double groundIslandRadius = treeRingOuter + 2;
const double cliffHeight = 12;

const int cliffRockCount = 22;
const double cliffRockRadialSpread = 4;
const double cliffRockMinScale = 1.8;
const double cliffRockMaxScale = 5.0;
const double cliffRockSpike = 0.75;

const double waveCrashInterval = 2.8;
const double waveCrashJitter = 2.8;
const double waveCrashRise = 0.6;

const double oceanLevel = -5;

const double oceanHalfExtent = 700;

// The chop octave runs at 2.6x the swell, so the grid has to resolve it:
// at 96 the crests fell between vertices and read as a slow heave.
const int oceanGridSegments = 144;

const double oceanWaveHeight = 2.4;

const double oceanWaveScale = 0.05;

const double propScaleJitterMin = 0.85;
const double propScaleJitterMax = 1.2;

final Vector3 sunDirection = Vector3(0.62, 0.34, 0.42);

const double sunIntensityScale = 1.1;
const double shadowMaxDistance = 70;
const double sceneExposure = 1.05;

/// Penumbra width under `pcss`. Wider than the real sun, which reads
/// knife-sharp at arena scale.
const double sunAngularRadius = 0.02;

/// `agx` holds highlight hue on the fire gushes; `aces` is the swap back.
const ToneMappingMode sceneToneMapping = ToneMappingMode.aces;

const double autoExposureStrength = 0.45;
const double autoExposureCompensation = 0.1;

final Vector3 skyGroundColor = Vector3(0.05, 0.13, 0.17);

const double fogVisibilityDistance = 800;
const double fogHeightFalloff = 0.07;

const double fogSkyColorInfluence = 0.35;

const double fogMaxOpacity = 0.42;

const double fogCutoffDistance = 150;

final Vector3 fogColor = Vector3(0.42, 0.47, 0.5);

const double godRaysIntensity = 0.45;
const double godRaysDensity = 0.4;
const double godRaysMaxDistance = 120;

const double sceneContrast = 1.03;
const double sceneSaturation = 1.05;
const double sceneColorTemperature = 0.06;
const double sceneVignetteIntensity = 0.22;
const double sceneVignetteRadius = 0.85;
const double sceneVignetteSmoothness = 0.6;

/// Grass blades used by the ultra quality preset.
const int grassBladeCount = 80000;

/// Where cascade 0 ends, out of [shadowMaxDistance].
///
/// The boom sits ten units behind the player, so everything the eye
/// actually audits is inside this radius. Pinning it holds one cascade's
/// full resolution there instead of letting the split scheme spend it on
/// the treeline.
const double shadowFirstCascadeFarBound = 18;

/// Fraction of each cascade tile that cross-fades into the next. Costs a
/// second lookup only for fragments inside the band.
const double shadowCascadeOverlap = 0.15;

/// The irradiance volume, placed by hand rather than fitted. fitScene would
/// swallow the ocean's 700-unit grid and spread every probe over open water.
/// Half-size, centred on [giVolumeCenterHeight]: wide enough to hold the
/// plateau and the orbiting camera, which has to be inside it to select it.
final Vector3 giVolumeExtents = Vector3(28, 12, 28);
const double giVolumeCenterHeight = 3;

/// Roughly one probe every three units.
final Vector3 giResolution = Vector3(16, 8, 16);

/// The clearing is lit by a low sun off warm ground, so the bounce is
/// strong. Held back from 1.0 so it reads as fill, not a second sun.
const double giIntensity = 0.75;

typedef QualityPreset = ({
  String label,
  int blades,
  double renderScale,
  bool ambientOcclusion,
  bool godRays,
  bool softParticles,
  bool autoExposure,
  AntiAliasingMode antiAliasing,
  DirectionalShadowFilter shadowFilter,
  // 0 hands cascades off hard, which reads as a seam across the clearing
  // floor where the resolution steps.
  double cascadeOverlap,
  // Grounds what cascade resolution misses: feet on grass, weapon on body.
  bool contactShadows,
  // Denser fields need wider blades. At one width for every count the extra
  // blades land as sub-pixel slivers, which shimmer instead of thickening.
  double bladeWidthScale,
  // The probe field. Desktop only: it forces the normals prepass and adds
  // the injection, blend, and filter passes.
  bool globalIllumination,
});

const List<QualityPreset> qualityPresets = [
  (
    label: 'LOW',
    blades: 0,
    renderScale: 0.6,
    ambientOcclusion: false,
    godRays: false,
    softParticles: false,
    autoExposure: false,
    // Three post passes buy little at 0.6 scale; msaa where the backend
    // has it is the cheaper edge.
    antiAliasing: AntiAliasingMode.auto,
    shadowFilter: DirectionalShadowFilter.bilinearPcf,
    cascadeOverlap: 0,
    contactShadows: false,
    globalIllumination: false,
    bladeWidthScale: 1.0,
  ),
  (
    label: 'MED',
    blades: 32000,
    renderScale: 0.75,
    ambientOcclusion: false,
    godRays: false,
    softParticles: false,
    autoExposure: false,
    antiAliasing: AntiAliasingMode.auto,
    // Smooth analog penumbras inside the same 16-sample budget the stepped
    // fixedPcf grid was spending.
    shadowFilter: DirectionalShadowFilter.bilinearPcf,
    cascadeOverlap: shadowCascadeOverlap,
    contactShadows: false,
    globalIllumination: false,
    bladeWidthScale: 1.0,
  ),
  (
    label: 'HIGH',
    blades: 48000,
    renderScale: 0.85,
    ambientOcclusion: true,
    godRays: false,
    softParticles: false,
    autoExposure: false,
    // Trades 4x msaa's geometric edges for smaa's far gentler treatment of
    // texture detail, which the grass field and bark need more.
    antiAliasing: AntiAliasingMode.smaa,
    shadowFilter: DirectionalShadowFilter.rotatedPoisson,
    cascadeOverlap: shadowCascadeOverlap,
    contactShadows: false,
    globalIllumination: false,
    bladeWidthScale: 1.0,
  ),
  (
    label: 'ULTRA',
    blades: grassBladeCount,
    renderScale: 1.0,
    ambientOcclusion: true,
    godRays: true,
    softParticles: true,
    autoExposure: true,
    antiAliasing: AntiAliasingMode.smaa,
    shadowFilter: DirectionalShadowFilter.rotatedPoisson,
    cascadeOverlap: shadowCascadeOverlap,
    contactShadows: false,
    globalIllumination: true,
    bladeWidthScale: 1.0,
  ),
];

final int defaultQualityLevel = heavyAtmospherics ? 3 : 2;

const double grassFieldRadius = treeRingInner + 2;
const double grassFalloffStart = arenaRadius;

const double grassRegrowSeconds = 14;

const int grassFieldSeed = 11;
const double grassWindStrength = 0.28;
const double grassSwayScale = 0.3;

final Vector2 windDirection = Vector2(0.8, 0.6);

const double stageCameraOrbitRadius = 16.5;
const double stageCameraHeight = 3.8;

const double stageCameraOrbitSpeed = 0.07;
