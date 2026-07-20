/// The stage's settings block: world units, arena dimensions, light, fog,
/// god rays, and the grass budget. Every value the clearing is built from is
/// a named constant here (task 5's "one settings block" rule).
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:vector_math/vector_math.dart' show Vector2, Vector3;

/// Heavy atmospherics (fog, god rays) measured too expensive on some mobile
/// GPUs without a visible payoff yet — desktop-only until tuned on device.
final bool heavyAtmospherics =
    defaultTargetPlatform != TargetPlatform.android &&
    defaultTargetPlatform != TargetPlatform.iOS;

// --- World units ---

/// KayKit medium-rig characters are authored ~2.2–2.5 units tall. The
/// slice originally pinned the knight at 1.8 world units, but against a
/// 14 u arena the fighters read as small and their reach as short — so
/// the pin is now 2.6 u (a heroic scale that fills the frame and lets the
/// swing arcs cover real ground). One shared factor keeps the kit's
/// relative proportions (barbarian lands at ~2.45).
const double characterScale = 2.6 / 2.543;

/// Yaw the model wrappers apply to land imported fronts on our +Z-forward
/// facing convention. KayKit characters import facing +Z: no flip.
const double characterModelYaw = 0;

/// Nature-pack props are used at author scale (1 unit ≈ 1 m, consistent with
/// the 1.8 u knight); the per-placement jitter below adds variety.
const double propScale = 1.0;

// --- Arena (the clearing) ---

/// Radius of the flat fighting circle.
const double arenaRadius = 14;

/// Fighters are clamped inside this radius (arena minus a body margin), the
/// seam the Phase-2 movement system consumes. See `data/arena.dart`.
const double arenaBoundsRadius = arenaRadius - 0.9;

/// Gravity is only load-bearing for grounding; combat movement is kinematic.
const double gravityStrength = 20;

/// Half-extent of the static ground slab (visual quad and collider).
const double groundHalfExtent = 60;

/// Thickness of the ground collider slab below y = 0.
const double groundThickness = 1;

// --- Forest ring (dressing; L4 theater) ---

/// Placement seed: the clearing re-lays identically every boot.
const int clearingSeed = 41;

/// Trees ring the arena between these radii — dense enough to close the
/// level off visually everywhere except the cliff gap.
const double treeRingInner = 17;
const double treeRingOuter = 24;
const int treeCount = 64;

/// Rocks and bushes scatter between the arena edge and the treeline.
const double scatterInner = arenaRadius + 1.5;
const double scatterOuter = treeRingInner + 4;
const int rockCount = 14;
const int bushCount = 26;

/// Underbrush: a bush ring hugging the treeline's feet, sealing the gaps
/// between trunks at eye level.
const int underbrushCount = 36;
const double underbrushRadius = treeRingInner - 1.5;
const double underbrushJitter = 0.9;

// --- The cliff and the sea ---

/// The treeline opens toward the sun, and the plateau drops away there:
/// god rays over water in the distance.
final double cliffAzimuth = math.atan2(sunDirection.x, sunDirection.z);
const double cliffHalfAngle = 0.6;

/// The plateau the whole clearing sits on; its wall is the cliff.
///
/// Deliberately CLOSE to the treeline. The rim used to sit 21 units past
/// the arena edge, which put the drop — and therefore the whole reason
/// there is a sea at all — outside anywhere you could see it from a
/// fight. The clearing is tighter now and the rim sits just past the
/// trees, so the gap in the treeline actually shows you a cliff.
const double groundIslandRadius = treeRingOuter + 2;
const double cliffHeight = 12;

/// The sea: enough below the plateau top to read as a drop, high enough
/// that a real band of water shows over the rim from the arena (the rim
/// hides everything nearer than ~rim × (1 + depth/eye-height)).
const double oceanLevel = -5;

/// Out to the horizon; past this the sky's ground band takes over in the
/// matching sea color.
const double oceanHalfExtent = 700;

/// Ocean grid tessellation per side (the wave vertex stage needs verts).
/// Doubled for the bigger swell: a tall wave across a coarse grid is a
/// row of folded facets, not water.
const int oceanGridSegments = 96;

/// The swell. Tall enough that the horizon visibly rises and falls —
/// this is the sea seen from a clifftop, so the tide is most of what
/// makes it read as water rather than a blue plane.
const double oceanWaveHeight = 2.4;

/// Wavelength, inverted: bigger means choppier. Kept long, so the swell
/// rolls rather than ripples.
const double oceanWaveScale = 0.05;

/// Per-prop uniform scale jitter (multiplied onto [propScale]).
const double propScaleJitterMin = 0.85;
const double propScaleJitterMax = 1.2;

// --- Sun, sky, fog, rays (task 5) ---

/// Low-afternoon sun: long shadows across the clearing, shafts through the
/// treeline. Normalized when used.
final Vector3 sunDirection = Vector3(0.62, 0.34, 0.42);

const double sunIntensityScale = 1.1;
const double shadowMaxDistance = 70;
const double sceneExposure = 1.05;

/// The sky below the horizon: deep sea, so the ocean plane's far edge
/// dissolves into it instead of ending on a brown band.
final Vector3 skyGroundColor = Vector3(0.05, 0.13, 0.17);

/// Fog reaches low-contrast haze at this distance; height falloff keeps it
/// ground-hugging so the treeline dissolves before the sky does.
const double fogVisibilityDistance = 800;
const double fogHeightFalloff = 0.07;

/// Kept low: toward the sun the sky sample is nearly white, and a high
/// influence whitewashes everything distant.
const double fogSkyColorInfluence = 0.35;

/// Fog never fully whites anything out — the sea across the cliff gap
/// keeps at least this much of its own color at any distance.
const double fogMaxOpacity = 0.42;

/// How far fog reaches before it stops entirely.
///
/// This used to be 90, which was short of where the sea began and left
/// the water rendering perfectly clean — deliberately, because the
/// original tuning had the whole ocean converging to fog colour and
/// reading as a white wall. Now the rim is closer the sea starts closer
/// too, and a LITTLE haze over the water is wanted: enough that distance
/// reads, not enough to bleach it.
///
/// The pair matters more than either value. This sets how far the haze
/// reaches; [fogMaxOpacity] caps how thick it can ever get. Raising this
/// without lowering that is what produced the white wall the first time.
const double fogCutoffDistance = 150;

/// Flat fog tone (the non-sky share): kept muted so distance haze greys
/// rather than whites.
final Vector3 fogColor = Vector3(0.42, 0.47, 0.5);

/// God rays: shafts through the treeline and across the water in the
/// cliff gap (still tuned short of a lens flare).
const double godRaysIntensity = 0.45;
const double godRaysDensity = 0.4;
const double godRaysMaxDistance = 120;

/// Post: a light warm grade and a soft vignette (scene_game's recipe, toned
/// for daylight).
const double sceneContrast = 1.03;
const double sceneSaturation = 1.05;
const double sceneColorTemperature = 0.06;
const double sceneVignetteIntensity = 0.22;
const double sceneVignetteRadius = 0.85;
const double sceneVignetteSmoothness = 0.6;

// --- Grass (task 6, at the Phase-0 measured budget) ---

/// Card count for the whole field — the density dial. The whole field is
/// one baked `MeshGeometry` and therefore one draw call, so this trades
/// against vertex cost rather than draw calls (see `vfx/grass_field.dart`
/// for why it is not instanced).
const int grassCardCount = 8000;

/// The field extends under the treeline and thins with distance: full
/// density inside [grassFalloffStart], zero at [grassFieldRadius].
const double grassFieldRadius = treeRingInner + 2;
const double grassFalloffStart = arenaRadius;

const int grassFieldSeed = 11;
const double grassWindStrength = 0.28;
const double grassSwayScale = 0.3;

// --- Wind dramaturgy (task 18) ---

/// Strength multipliers the wind eases toward: a gust while the pack
/// circles, near-still while a barbarian telegraphs.
const double windGustStrength = 1.35;
const double windCalmStrength = 0.35;

/// How fast the strength eases toward its target (per second).
const double windEaseRate = 2.5;

/// Horizontal wind heading (normalized when used).
final Vector2 windDirection = Vector2(0.8, 0.6);

// --- Stage camera (placeholder until the Phase-2 CameraRig) ---

const double stageCameraOrbitRadius = 16.5;
const double stageCameraHeight = 3.2;

/// Radians per second of the slow show-off orbit around the empty stage.
const double stageCameraOrbitSpeed = 0.07;
