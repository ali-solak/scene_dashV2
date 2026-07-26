/// Combat camera state.
library;

import 'package:vector_math/vector_math.dart' show Vector3;

class CameraRig {
  /// World-space camera position, mutated in place each frame.
  final Vector3 position = Vector3(0, 2.6, -5.5);

  /// What the camera looks at.
  final Vector3 target = Vector3(0, 1.3, 0);

  /// The rig's smoothed heading; camera forward is `(sin yaw, 0, cos yaw)`.
  double yaw = 0;

  /// Orbit elevation in radians.
  double pitch = 0.3;

  /// Seconds left in the opening camera move.
  double intro = 0;
}
