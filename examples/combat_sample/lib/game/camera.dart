/// The combat camera driven by ECS-updated [CameraRig] state.
///
/// Built once and reused: [PerspectiveCamera] holds the rig's
/// position/target vectors by reference, and the rig mutates them in place
/// each frame (free follow unlocked; behind-player lock framing — see the
/// player feature's `updateCameraRig`).
library;

import 'package:flutter_scene/scene.dart';

import 'camera_rig.dart';

PerspectiveCamera? _camera;

Camera buildCombatCamera(Duration elapsed, CameraRig rig) {
  return _camera ??= PerspectiveCamera(
    position: rig.position,
    target: rig.target,
  );
}
