/// The camera rig: a plain resource written by the player feature's
/// `updateCameraRig` each frame and read by `main`'s `cameraBuilder`
/// (scene_game's pattern — the framework never owns cameras).
library;

import 'package:vector_math/vector_math.dart' show Vector3;

class CameraRig {
  /// World-space camera position, mutated in place each frame.
  final Vector3 position = Vector3(0, 2.6, -5.5);

  /// What the camera looks at.
  final Vector3 target = Vector3(0, 1.3, 0);

  /// The rig's smoothed heading; camera forward is `(sin yaw, 0, cos yaw)`.
  double yaw = 0;

  /// Orbit elevation in radians: 0 looks level with the fighter, higher
  /// looks down on them. Player-controlled free, eased while locked.
  double pitch = 0.3;

  /// Impulse set by heavy connects (rules); the camera system rides and
  /// decays it.
  double kick = 0;
}
