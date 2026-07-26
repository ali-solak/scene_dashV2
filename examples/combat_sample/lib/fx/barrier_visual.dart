/// Builds the shield barrier.
library;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

/// Fallback barrier color.
final Vector4 _fallbackTint = Vector4(0.42, 0.72, 1.0, 1);

/// Fallback alpha range.
const double _alphaFull = 0.20;
const double _alphaLast = 0.07;

/// What a block adds on top of the fallback, decaying over the flash.
const double _flashAlpha = 0.45;

/// Builds the barrier bubble.
({Node node, Material material}) buildBarrierSphere({
  required double radius,
  required double height,
  PreprocessedMaterial? authored,
}) {
  final material =
      authored ??
      (UnlitMaterial()
        ..alphaMode = AlphaMode.blend
        ..baseColorFactor = Vector4.copy(_fallbackTint)
        ..vertexColorWeight = 0);
  final node =
      Node(
          name: 'barrier',
          localTransform: Matrix4.translation(Vector3(0, height, 0)),
        )
        // Transparent bubble.
        ..mesh = Mesh(
          SphereGeometry(radius: radius, segments: 32, rings: 16),
          material,
        );
  return (node: node, material: material);
}

/// Drives the bubble from what the barrier has left.
///
/// [remaining] is charges-left over charges-raised-with (1 → 0), [flash]
/// is 1 on the frame of a block decaying to 0 across the flash window,
/// and [hitFrom] is the world-space direction the last blow struck from.
void setBarrierCharge(
  Material material, {
  required double time,
  required double remaining,
  required double flash,
  required Vector3 hitFrom,
}) {
  final charge = remaining.clamp(0.0, 1.0);
  final flare = flash.clamp(0.0, 1.0);

  if (material is PreprocessedMaterial) {
    material.parameters
      ..setFloat('time', time)
      ..setFloat('charge', charge)
      ..setFloat('hit', flare)
      ..setVec3('hit_dir', hitFrom);
    return;
  }

  // Fallback shell state.
  if (material is! UnlitMaterial) return;
  final base = _alphaLast + (_alphaFull - _alphaLast) * charge;
  material.baseColorFactor = Vector4(
    _fallbackTint.x + (1 - _fallbackTint.x) * flare,
    _fallbackTint.y + (1 - _fallbackTint.y) * flare,
    _fallbackTint.z + (1 - _fallbackTint.z) * flare,
    (base + _flashAlpha * flare).clamp(0.0, 1.0),
  );
}
