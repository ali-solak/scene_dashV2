part of '../rocks.dart';

/// Up to this many flaming rocks get a trail at once; extra rocks skip it.
const int _trailRockCap = 24;

/// Puffs drawn behind each flaming rock.
const int _puffsPerRock = 3;

/// Builds the shared flame-trail pool: a small unlit emissive sphere, one
/// instance per puff across every flaming rock.
InstancedPool buildFlamePool() => InstancedPool(
  geometry: SphereGeometry(radius: 1, segments: 8, rings: 4),
  material: UnlitMaterial()
    ..baseColorFactor = Vector4(1.0, 0.34, 0.05, 1)
    ..vertexColorWeight = 0,
  capacity: _trailRockCap * _puffsPerRock,
);
