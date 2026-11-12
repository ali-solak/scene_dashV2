import 'package:scene_dash_v2_core/advanced.dart';
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3;

import 'scene_transform.dart';

final class InterpolateTransform {
  final Vector3 _translation = Vector3.zero();
  final Quaternion _rotation = Quaternion.identity();
  final Vector3 _scale = Vector3.all(1);
  bool _primed = false;

  InterpolateTransform();

  void snap() => _primed = false;

  void capture(SceneTransform transform) {
    _translation.setFrom(transform.translation);
    _rotation.setFrom(transform.rotation);
    _scale.setFrom(transform.scale);
    _primed = true;
  }

  void blendInto(
    SceneTransform current,
    double alpha,
    Vector3 translation,
    Quaternion rotation,
    Vector3 scale,
  ) {
    if (!_primed) {
      capture(current);
      translation.setFrom(current.translation);
      rotation.setFrom(current.rotation);
      scale.setFrom(current.scale);
      return;
    }
    final from = _translation.storage;
    final to = current.translation.storage;
    translation.setValues(
      from[0] + (to[0] - from[0]) * alpha,
      from[1] + (to[1] - from[1]) * alpha,
      from[2] + (to[2] - from[2]) * alpha,
    );
    final fs = _scale.storage;
    final ts = current.scale.storage;
    scale.setValues(
      fs[0] + (ts[0] - fs[0]) * alpha,
      fs[1] + (ts[1] - fs[1]) * alpha,
      fs[2] + (ts[2] - fs[2]) * alpha,
    );
    final a = _rotation.storage;
    final b = current.rotation.storage;
    final sign = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3] < 0
        ? -1.0
        : 1.0;
    rotation
      ..setValues(
        a[0] + (b[0] * sign - a[0]) * alpha,
        a[1] + (b[1] * sign - a[1]) * alpha,
        a[2] + (b[2] * sign - a[2]) * alpha,
        a[3] + (b[3] * sign - a[3]) * alpha,
      )
      ..normalize();
  }
}

final class TransformCapture {
  Query2<InterpolateTransform, SceneTransform>? _query;

  void initialize(World world) {
    world
      ..ensureObjectStore<InterpolateTransform>()
      ..ensureObjectStore<SceneTransform>();
    _query = world.rawQuery2<InterpolateTransform, SceneTransform>();
  }

  void capture() => _query?.each(_capture);

  static void _capture(
    Entity entity,
    InterpolateTransform interpolation,
    SceneTransform transform,
  ) => interpolation.capture(transform);
}
