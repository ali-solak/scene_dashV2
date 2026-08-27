/// Replacement geometry for `WidgetComponent`.
///
/// flutter_scene 0.23 flipped model-space front faces to CCW but left
/// `WidgetComponent._quadGeometry` on the old winding, so the default
/// surface is back-facing and its always-blended material culls it. This
/// is the same quad wound the way `CuboidGeometry`'s +Z face is wound.
/// Delete it once the engine's quad is flipped.
library;

import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_scene/scene.dart' show Geometry, MeshGeometry;

Geometry widgetQuad({required Size size, required double worldHeight}) {
  final halfHeight = worldHeight / 2;
  final halfWidth = halfHeight * (size.width / size.height);
  return MeshGeometry.fromArrays(
    positions: Float32List.fromList([
      halfWidth, -halfHeight, 0, //
      -halfWidth, -halfHeight, 0, //
      -halfWidth, halfHeight, 0, //
      halfWidth, halfHeight, 0,
    ]),
    texCoords: Float32List.fromList([0, 1, 1, 1, 1, 0, 0, 0]),
    indices: const [0, 3, 1, 3, 2, 1],
  );
}
