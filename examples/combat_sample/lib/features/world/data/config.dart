library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:vector_math/vector_math.dart' show Vector2, Vector3;

final bool isMobile =
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

final bool heavyAtmospherics = !isMobile;

final bool runtimeRenderScaleIsSafe = !isMobile;

const double characterScale = 2.6 / 2.543;

const double characterModelYaw = 0;

const double propScale = 1.0;

const double arenaRadius = 14;

const double arenaBoundsRadius = arenaRadius - 0.9;

const double gravityStrength = 20;

const double groundHalfExtent = 60;

const double groundThickness = 1;

const int clearingSeed = 41;

const double treeRingInner = 17;
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

const int oceanGridSegments = 96;

const double oceanWaveHeight = 2.4;

const double oceanWaveScale = 0.05;

const double propScaleJitterMin = 0.85;
const double propScaleJitterMax = 1.2;

final Vector3 sunDirection = Vector3(0.62, 0.34, 0.42);

const double sunIntensityScale = 1.1;
const double shadowMaxDistance = 70;
const double sceneExposure = 1.05;

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

const int grassCardCount = 8000;

typedef QualityPreset = ({
  String label,
  int cards,
  double renderScale,
  bool ambientOcclusion,
  bool godRays,
});

const List<QualityPreset> qualityPresets = [
  (
    label: 'LOW',
    cards: 0,
    renderScale: 0.6,
    ambientOcclusion: false,
    godRays: false,
  ),
  (
    label: 'MED',
    cards: 4000,
    renderScale: 0.75,
    ambientOcclusion: false,
    godRays: false,
  ),
  (
    label: 'HIGH',
    cards: 6000,
    renderScale: 0.85,
    ambientOcclusion: true,
    godRays: false,
  ),
  (
    label: 'ULTRA',
    cards: grassCardCount,
    renderScale: 1.0,
    ambientOcclusion: true,
    godRays: true,
  ),
];

final int defaultQualityLevel = heavyAtmospherics ? 3 : 2;

const double grassFieldRadius = treeRingInner + 2;
const double grassFalloffStart = arenaRadius;

const int grassFieldSeed = 11;
const double grassWindStrength = 0.28;
const double grassSwayScale = 0.3;

const double windGustStrength = 1.35;
const double windCalmStrength = 0.35;

const double windEaseRate = 2.5;

final Vector2 windDirection = Vector2(0.8, 0.6);

const double stageCameraOrbitRadius = 16.5;
const double stageCameraHeight = 3.2;

const double stageCameraOrbitSpeed = 0.07;
