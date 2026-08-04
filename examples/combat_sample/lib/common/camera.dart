/// The combat camera. Built once: [PerspectiveCamera] holds the rig's
/// vectors by reference and the rig mutates them in place.
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
