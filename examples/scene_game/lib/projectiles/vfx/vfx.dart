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

/// A flat ring in the XZ plane, radius ~0.5, used for the impact shockwave.
MeshGeometry ringGeometry({int segments = 32, double thickness = 0.12}) {
  final inner = (0.5 - thickness * 0.5).clamp(0.02, 0.49);
  final outer = 0.5 + thickness * 0.5;
  final positions = Float32List((segments + 1) * 2 * 3);
  final normals = Float32List((segments + 1) * 2 * 3);
  final texCoords = Float32List((segments + 1) * 2 * 2);
  final indices = <int>[];

  for (var i = 0; i <= segments; i++) {
    final a = i / segments * math.pi * 2;
    final c = math.cos(a);
    final s = math.sin(a);
    final innerIndex = i * 2;
    final outerIndex = innerIndex + 1;

    positions[innerIndex * 3] = c * inner;
    positions[innerIndex * 3 + 1] = 0;
    positions[innerIndex * 3 + 2] = s * inner;
    positions[outerIndex * 3] = c * outer;
    positions[outerIndex * 3 + 1] = 0;
    positions[outerIndex * 3 + 2] = s * outer;
    normals[innerIndex * 3 + 1] = 1;
    normals[outerIndex * 3 + 1] = 1;
    texCoords[innerIndex * 2] = 0;
    texCoords[innerIndex * 2 + 1] = i / segments;
    texCoords[outerIndex * 2] = 1;
    texCoords[outerIndex * 2 + 1] = i / segments;

    if (i < segments) {
      final a0 = i * 2;
      final b0 = a0 + 1;
      final a1 = a0 + 2;
      final b1 = a0 + 3;
      indices.addAll([a0, b0, a1, b0, b1, a1]);
    }
  }

  return MeshGeometry.fromArrays(
    positions: positions,
    normals: normals,
    texCoords: texCoords,
    indices: indices,
  );
}
