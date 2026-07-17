part of '../projectiles.dart';

/// A translucent additive-ish glow material for projectile and impact visuals.
PhysicallyBasedMaterial glowMaterial(Vector4 color, {double alpha = 1}) {
  final visible = Vector4(color.x, color.y, color.z, color.w * alpha);
  return PhysicallyBasedMaterial()
    ..baseColorFactor = visible
    ..emissiveFactor = Vector4(color.x * 1.6, color.y * 1.6, color.z * 1.6, 1)
    ..metallicFactor = 0
    ..roughnessFactor = 0.18
    ..alphaMode = AlphaMode.blend;
}
