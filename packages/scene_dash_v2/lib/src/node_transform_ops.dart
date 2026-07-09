import 'package:flutter_scene/scene.dart' show Node;
import 'package:vector_math/vector_math.dart';

/// Allocation-free transform helpers for direct-node-path systems.
///
/// `flutter_scene` node matrices must be *reassigned* after an in-place edit
/// so the node's dirty flag trips; and `getTranslation()` allocates a fresh
/// vector per call. These extensions encode both rules once, so per-frame
/// systems neither rediscover the idioms nor allocate:
///
/// ```dart
/// node.setLocalUniform(0, bob, 0, pulse);          // pose a VFX child
/// node.globalTranslationInto(_scratch);            // read a world position
/// ```
extension NodeTransformOps on Node {
  /// Rebuilds the local transform as translate([x], [y], [z]) then scale
  /// ([sx], [sy], [sz]), mutating the existing matrix in place — no
  /// allocation — and reassigning it to trip the node's dirty flag.
  void setLocalTRS(
    double x,
    double y,
    double z,
    double sx,
    double sy,
    double sz,
  ) {
    final m = localTransform
      ..setIdentity()
      ..setTranslationRaw(x, y, z)
      ..scaleByDouble(sx, sy, sz, 1);
    localTransform = m;
  }

  /// [setLocalTRS] with one uniform [scale].
  void setLocalUniform(double x, double y, double z, double scale) =>
      setLocalTRS(x, y, z, scale, scale, scale);

  /// Writes this node's world-space translation into [out] — the
  /// allocation-free replacement for `globalTransform.getTranslation()`.
  /// (`globalTransform` itself returns the node's cached matrix.)
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
