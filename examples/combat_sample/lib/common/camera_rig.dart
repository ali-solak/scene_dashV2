/// Combat camera state.
library;

import 'package:flutter_scene/kit.dart' show CameraShake;
import 'package:vector_math/vector_math.dart' show Vector3;

class CameraRig {
  /// World-space camera position: [basePosition] plus this frame's shake.
  final Vector3 position = Vector3(0, 2.6, -5.5);

  /// What the camera looks at.
  final Vector3 target = Vector3(0, 1.3, 0);

  /// The boom's smoothed position, before shake. Kept apart so the ease
  /// smooths the boom and not the shake, which would ring.
  final Vector3 basePosition = Vector3(0, 2.6, -5.5);

  /// The framing point before shake.
  final Vector3 baseTarget = Vector3(0, 1.3, 0);

  /// Trauma-decay shake, fed by landed hits.
  final CameraShake shake = CameraShake(
    decayRate: 2.4,
    frequency: 22,
    maxTranslation: Vector3(0.22, 0.16, 0.1),
    maxRotation: Vector3(0.035, 0.035, 0.02),
  );

  /// The rig's smoothed heading; camera forward is `(sin yaw, 0, cos yaw)`.
  double yaw = 0;

  /// Orbit elevation in radians.
  double pitch = 0.3;

  /// Seconds left in the opening camera move.
  double intro = 0;
}
