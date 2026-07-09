part of '../collectables.dart';

/// Builds the shared shield-deflection pool: a small bright shard, one instance
/// per deflection puff. One node, one draw call for every deflection burst.
InstancedPool buildDeflectPool() => InstancedPool(
  geometry: SphereGeometry(radius: 0.18, segments: 10, rings: 5),
  material: PhysicallyBasedMaterial()
    ..baseColorFactor = Vector4(0.6, 0.9, 1.0, 0.5)
    ..emissiveFactor = Vector4(0.6, 1.2, 1.6, 1)
    ..metallicFactor = 0
    ..roughnessFactor = 0.2
    ..alphaMode = AlphaMode.blend,
  capacity: _deflectCapacity,
);
