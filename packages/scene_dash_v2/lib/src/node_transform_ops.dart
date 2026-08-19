import 'package:flutter_scene/scene.dart' show Node;
import 'package:vector_math/vector_math.dart';

/// Transform helpers for scene nodes.
extension NodeTransformOps on Node {
  /// Sets local translation and scale.
  void setLocalTRS(
    double x,
    double y,
    double z,
    double sx,
    double sy,
    double sz,
  ) {
    mutateLocalTransform(
      (m) => m
        ..setIdentity()
        ..setTranslationRaw(x, y, z)
        ..scaleByDouble(sx, sy, sz, 1),
    );
  }

  /// [setLocalTRS] with one uniform [scale].
  void setLocalUniform(double x, double y, double z, double scale) =>
      setLocalTRS(x, y, z, scale, scale, scale);

  /// Writes the world position into [out].
  void globalTranslationInto(Vector3 out) {
    final s = globalTransform.storage;
    out.setValues(s[12], s[13], s[14]);
  }

  /// Writes this node's local-space translation into [out].
  void localTranslationInto(Vector3 out) {
    final s = localTransform.storage;
    out.setValues(s[12], s[13], s[14]);
  }
}
