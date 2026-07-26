part of '../player.dart';

/// The follow camera: orbit, lock-on framing, and the opening push-in.
void installPlayerCamera(GameBuilder game) {
  game.addSystem(
    Schedules.fixedUpdate,
    updateCameraRig,
    inSet: GameSets.resolution,
    reads: const {Player, PlayerMotion, SceneTransform, Target},
  );
}

/// Follows the fight (writes the [CameraRig] that `cameraBuilder` in
/// `main` reads) with a souls orbit: a yaw/pitch sphere around the
/// fighter's chest, position-smoothed. Free = pointer-owned yaw and
/// pitch; locked = yaw steered toward the target, focus slid toward the
/// pair's midpoint so both fighters stay framed.
void updateCameraRig(World world) {
  final rig = world.resource<CameraRig>();
  final look = world.resource<LookInput>();
  final row = world
      .query2<PlayerMotion, SceneTransform>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (player, motion, transform) = row;
  final targetTransform = _targetTransform(world, player);
  final position = transform.translation;
  final dt = world.dt;

  // The title shot: a wide, slow orbit of the clearing. It frames the
  // place, not the fighter; the push-in at run start introduces him.
  if (world.state<GameStatus>() == GameStatus.title) {
    rig
      ..yaw += titleOrbitRate * dt
      ..pitch = titleCameraPitch;
    rig.target.setValues(0, cameraFocusHeight, 0);
    final horizontal = titleCameraDistance * math.cos(rig.pitch);
    rig.position.setValues(
      rig.target.x - math.sin(rig.yaw) * horizontal,
      rig.target.y + titleCameraDistance * math.sin(rig.pitch),
      rig.target.z - math.cos(rig.yaw) * horizontal,
    );
    return;
  }

  if (targetTransform != null) {
    // The lock owns the framing; manual look is discarded, not banked.
    look.takeYawDelta();
    look.takePitchDelta();
    final desiredYaw = math.atan2(
      targetTransform.translation.x - position.x,
      targetTransform.translation.z - position.z,
    );
    final yawBlend = 1 - math.exp(-cameraYawSharpness * dt);
    rig.yaw += angleDifference(desiredYaw, rig.yaw) * yawBlend;
    final pitchBlend = 1 - math.exp(-cameraPitchSharpness * dt);
    rig.pitch += (cameraLockedPitch - rig.pitch) * pitchBlend;
  } else {
    rig.yaw += look.takeYawDelta() * lookYawSensitivity;
    rig.pitch = (rig.pitch + look.takePitchDelta() * lookPitchSensitivity)
        .clamp(cameraPitchMin, cameraPitchMax);
  }

  rig.target.setValues(position.x, position.y + cameraFocusHeight, position.z);
  if (targetTransform != null) {
    rig.target.setValues(
      position.x +
          (targetTransform.translation.x - position.x) * lockedCameraBias,
      position.y + cameraFocusHeight,
      position.z +
          (targetTransform.translation.z - position.z) * lockedCameraBias,
    );
  }

  // Frame the player and target.
  var distance = cameraDistance;
  if (targetTransform != null) {
    final dx = targetTransform.translation.x - position.x;
    final dz = targetTransform.translation.z - position.z;
    final separation = math.sqrt(dx * dx + dz * dz);
    distance = (cameraDistance + separation * lockedDistanceGain).clamp(
      cameraDistance,
      maxLockedCameraDistance,
    );
  }
  final horizontal = distance * math.cos(rig.pitch);
  final desiredX = rig.target.x - math.sin(rig.yaw) * horizontal;
  // rig.target.y already carries cameraFocusHeight.
  final desiredY = rig.target.y + distance * math.sin(rig.pitch);
  final desiredZ = rig.target.z - math.cos(rig.yaw) * horizontal;
  // The opening push-in rides the existing smoothing: same desired
  // framing from the first frame, only the rate differs during the intro.
  var sharpness = cameraPositionSharpness;
  if (rig.intro > 0) {
    rig.intro = math.max(0, rig.intro - dt);
    sharpness = introCameraSharpness;
  }
  final positionBlend = 1 - math.exp(-sharpness * dt);
  rig.position.setValues(
    rig.position.x + (desiredX - rig.position.x) * positionBlend,
    rig.position.y + (desiredY - rig.position.y) * positionBlend,
    rig.position.z + (desiredZ - rig.position.z) * positionBlend,
  );
}
