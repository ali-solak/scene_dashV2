/// Combat camera state.
library;

import 'package:flutter_scene/kit.dart' show CameraShake;
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3;

class CameraRig {
  /// World-space boom position, before shake.
  final Vector3 position = Vector3(0, 2.6, -5.5);

  /// What the camera looks at, before shake.
  final Vector3 target = Vector3(0, 1.3, 0);

  /// Trauma-decay shake, fed by landed hits.
  final CameraShake shake = CameraShake(
    decayRate: 2.4,
    frequency: 22,
    maxTranslation: Vector3(0.22, 0.16, 0.1),
    maxRotation: Vector3(0.035, 0.035, 0.02),
  );

  final Matrix4 shakeOffset = Matrix4.identity();

  double yaw = 0;

  double pitch = 0.3;

  double intro = 0;

  double boom = double.infinity;
}
