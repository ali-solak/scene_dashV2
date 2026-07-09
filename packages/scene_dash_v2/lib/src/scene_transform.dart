import 'dart:math' as math;

import 'package:vector_math/vector_math.dart'
    show Matrix3, Matrix4, Quaternion, Vector3;

/// The standard transform component the integration synchronizes onto bound
/// nodes.
///
/// Holds a node-**local** translation, rotation and scale. Named
/// `SceneTransform` (not `Transform`) to avoid colliding with Flutter's
/// `Transform` widget. Games that already have their own transform type can use
/// `CustomSceneSyncPlugin<T>` instead.
///
/// ## Conventions
///
/// * All angles are in **radians**.
/// * [translation], [rotation] and [scale] are node-local. The integration
///   composes them into the node's local matrix; `flutter_scene` then performs
///   hierarchy propagation to world space.
/// * [rotation] is a unit quaternion. Methods that compose rotations
///   re-normalize to prevent drift; the absolute setters assume their inputs
///   are already normalized.
/// * Forward is **−Z** and up is **+Y** (the glTF / `flutter_scene` camera
///   convention) — see [lookAt].
///
/// ## Mutability
///
/// The [translation], [rotation] and [scale] fields are exposed directly and
/// remain freely mutable (e.g. `transform.translation.x += dx`). The methods
/// below are ergonomic helpers, not a sealed wrapper: there is intentionally no
/// dirty tracking, so direct field mutation and helper calls are equivalent.
final class SceneTransform {
  /// Node-local position.
  final Vector3 translation;

  /// Node-local orientation (unit quaternion).
  final Quaternion rotation;

  /// Node-local scale.
  final Vector3 scale;

  SceneTransform(double x, double y, double z)
    : translation = Vector3(x, y, z),
      rotation = Quaternion.identity(),
      scale = Vector3.all(1);

  SceneTransform.zero() : this(0, 0, 0);

  SceneTransform.fromVector(Vector3 position)
    : translation = position.clone(),
      rotation = Quaternion.identity(),
      scale = Vector3.all(1);

  SceneTransform.trs({
    Vector3? translation,
    Quaternion? rotation,
    Vector3? scale,
  }) : translation = translation?.clone() ?? Vector3.zero(),
       rotation = rotation?.clone() ?? Quaternion.identity(),
       scale = scale?.clone() ?? Vector3.all(1);

  // --- Translation ---

  double get x => translation.x;

  set x(double value) {
    translation.x = value;
  }

  double get y => translation.y;

  set y(double value) {
    translation.y = value;
  }

  double get z => translation.z;

  set z(double value) {
    translation.z = value;
  }

  /// Sets the absolute local translation.
  SceneTransform setTranslation(double x, double y, double z) {
    translation.setValues(x, y, z);
    return this;
  }

  /// Sets the absolute local translation from [value] (copied, not aliased).
  SceneTransform setTranslationFrom(Vector3 value) {
    translation.setFrom(value);
    return this;
  }

  /// Adds `(dx, dy, dz)` to the current local translation.
  SceneTransform translate(double dx, double dy, double dz) {
    translation
      ..x += dx
      ..y += dy
      ..z += dz;
    return this;
  }

  /// Adds [delta] to the current local translation.
  SceneTransform translateBy(Vector3 delta) {
    translation.add(delta);
    return this;
  }

  // --- Scale ---

  /// Sets a non-uniform local scale.
  SceneTransform setScale(double x, double y, double z) {
    scale.setValues(x, y, z);
    return this;
  }

  /// Sets a non-uniform local scale from [value] (copied, not aliased).
  SceneTransform setScaleFrom(Vector3 value) {
    scale.setFrom(value);
    return this;
  }

  /// Sets a uniform local scale on all three axes.
  SceneTransform setUniformScale(double value) {
    scale.setValues(value, value, value);
    return this;
  }

  // --- Rotation ---

  /// Sets the absolute orientation from [quaternion] (copied, not aliased).
  ///
  /// Assumes [quaternion] is normalized.
  SceneTransform setRotation(Quaternion quaternion) {
    rotation.setFrom(quaternion);
    return this;
  }

  /// Resets the orientation to identity (no rotation).
  SceneTransform setRotationIdentity() {
    rotation.setValues(0, 0, 0, 1);
    return this;
  }

  /// Sets the absolute orientation to a rotation of [radians] about local X.
  SceneTransform setRotationX(double radians) {
    final half = radians * 0.5;
    rotation.setValues(math.sin(half), 0, 0, math.cos(half));
    return this;
  }

  /// Sets the absolute orientation to a rotation of [radians] about local Y.
  SceneTransform setRotationY(double radians) {
    final half = radians * 0.5;
    rotation.setValues(0, math.sin(half), 0, math.cos(half));
    return this;
  }

  /// Sets the absolute orientation to a rotation of [radians] about local Z.
  SceneTransform setRotationZ(double radians) {
    final half = radians * 0.5;
    rotation.setValues(0, 0, math.sin(half), math.cos(half));
    return this;
  }

  /// Sets the absolute orientation from intrinsic Euler angles, in radians.
  ///
  /// [x] is pitch (about X), [y] is yaw (about Y), [z] is roll (about Z),
  /// applied as the intrinsic Y→X→Z composition used by `vector_math`'s
  /// `Quaternion.setEuler(yaw, pitch, roll)`.
  SceneTransform setRotationEuler(double x, double y, double z) {
    rotation.setEuler(y, x, z);
    return this;
  }

  /// Sets the absolute orientation to a rotation of [radians] about [axis].
  ///
  /// [axis] should be normalized.
  SceneTransform setRotationAxisAngle(Vector3 axis, double radians) {
    rotation.setAxisAngle(axis, radians);
    return this;
  }

  /// Post-multiplies the current orientation by [delta] (local-space rotation),
  /// then re-normalizes.
  SceneTransform rotate(Quaternion delta) {
    rotation
      ..setFrom(rotation * delta)
      ..normalize();
    return this;
  }

  /// Rotates by [radians] about the local X axis.
  SceneTransform rotateX(double radians) =>
      rotate(Quaternion.axisAngle(Vector3(1, 0, 0), radians));

  /// Rotates by [radians] about the local Y axis.
  SceneTransform rotateY(double radians) =>
      rotate(Quaternion.axisAngle(Vector3(0, 1, 0), radians));

  /// Rotates by [radians] about the local Z axis.
  SceneTransform rotateZ(double radians) =>
      rotate(Quaternion.axisAngle(Vector3(0, 0, 1), radians));

  // --- Copy & reset ---

  /// Copies translation, rotation and scale from [other].
  SceneTransform setFrom(SceneTransform other) {
    translation.setFrom(other.translation);
    rotation.setFrom(other.rotation);
    scale.setFrom(other.scale);
    return this;
  }

  /// Resets to the identity transform: zero translation, identity rotation,
  /// unit scale.
  SceneTransform setIdentity() {
    translation.setZero();
    rotation.setValues(0, 0, 0, 1);
    scale.setValues(1, 1, 1);
    return this;
  }

  // --- Matrix interop ---

  /// Replaces translation, rotation and scale by decomposing [matrix].
  ///
  /// Limitation: a `Matrix4` can encode shear and negative determinants that a
  /// translation + unit-quaternion + scale cannot represent losslessly.
  /// `vector_math`'s decomposition folds any reflection into the scale sign and
  /// drops shear, so `setFromMatrix(m).toMatrix()` is **not** guaranteed to
  /// equal `m` for sheared or mirrored matrices.
  SceneTransform setFromMatrix(Matrix4 matrix) {
    matrix.decompose(translation, rotation, scale);
    return this;
  }

  /// Composes translation, rotation and scale into a `Matrix4`.
  ///
  /// Pass [out] to write into an existing matrix and avoid allocation.
  Matrix4 toMatrix([Matrix4? out]) {
    final result = out ?? Matrix4.zero();
    result.setFromTranslationRotationScale(translation, rotation, scale);
    return result;
  }

  // --- Look-at ---

  /// Orients this transform so its local **−Z** axis points at [target] (in the
  /// same local space as [translation]) and its local **+Y** stays as close to
  /// [up] as possible. Defaults to up = +Y.
  ///
  /// Leaves the rotation unchanged if [target] coincides with [translation].
  /// If the look direction is parallel to [up], a fallback up axis is chosen so
  /// the result stays well-defined. Translation and scale are not modified.
  SceneTransform lookAt(Vector3 target, {Vector3? up}) {
    final forward = target - translation;
    if (forward.length2 < 1e-12) {
      return this; // Degenerate: target == position.
    }
    forward.normalize();

    // Local +Z points away from the target (camera/glTF convention).
    final zAxis = -forward;
    var upHint = up ?? Vector3(0, 1, 0);
    var xAxis = upHint.cross(zAxis);
    if (xAxis.length2 < 1e-12) {
      // up is parallel to the view direction: pick an orthogonal fallback.
      upHint = (zAxis.x.abs() < 0.9) ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
      xAxis = upHint.cross(zAxis);
    }
    xAxis.normalize();
    final yAxis = zAxis.cross(xAxis)..normalize();

    // The intended rotation maps the local basis onto (xAxis, yAxis, zAxis),
    // i.e. those are its columns. `Quaternion.setFromRotation` reads the matrix
    // such that `q.rotated(v) == matrixᵀ · v`, so transpose before converting.
    rotation
      ..setFromRotation(Matrix3.columns(xAxis, yAxis, zAxis)..transpose())
      ..normalize();
    return this;
  }
}
