/// The combat camera: a node carrying a `CameraComponent`, which registers
/// itself as the scene's primary. The rig aims it each frame.
library;

import 'package:flutter_scene/scene.dart';

import 'camera_rig.dart';

Node? _cameraNode;

void mountCombatCamera(Scene scene) {
  if (_cameraNode != null) return;
  final node = Node(name: 'combat-camera')
    ..addComponent(CameraComponent(activateOnMount: true));
  scene.root.add(node);
  _cameraNode = node;
}

void aimCombatCamera(CameraRig rig) {
  _cameraNode?.localTransform =
      Node.lookAtTransform(rig.position, rig.target) * rig.shakeOffset;
}
