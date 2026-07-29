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
  final row = world
      .query2<PlayerMotion, SceneTransform>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (player, _, transform) = row;
  final dt = world.dt;

  if (world.state<GameStatus>() == GameStatus.title) {
    _orbitTitle(rig, dt);
    return;
  }

  final position = transform.translation;
  final target = _targetTransform(world, player);
  _aim(rig, world.resource<LookInput>(), position, target, dt);
  _focus(rig, position, target);
  _ease(rig, _framingDistance(position, target), dt);
}

/// The title shot: a wide, slow orbit of the clearing. It frames the place,
/// not the fighter; the push-in at run start introduces him.
void _orbitTitle(CameraRig rig, double dt) {
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
}

/// Yaw and pitch: steered by the lock, or owned by the pointer.
void _aim(
  CameraRig rig,
  LookInput look,
  Vector3 position,
  SceneTransform? target,
  double dt,
) {
  if (target == null) {
    rig.yaw += look.takeYawDelta() * lookYawSensitivity;
    rig.pitch = (rig.pitch + look.takePitchDelta() * lookPitchSensitivity)
        .clamp(cameraPitchMin, cameraPitchMax);
    return;
  }
  // The lock owns the framing; manual look is discarded, not banked.
  look.takeYawDelta();
  look.takePitchDelta();
  final desiredYaw = math.atan2(
    target.translation.x - position.x,
    target.translation.z - position.z,
  );
  rig.yaw +=
      angleDifference(desiredYaw, rig.yaw) *
      (1 - math.exp(-cameraYawSharpness * dt));
  rig.pitch +=
      (cameraLockedPitch - rig.pitch) *
      (1 - math.exp(-cameraPitchSharpness * dt));
}

/// What the camera looks at: the fighter's chest, slid toward the target so
/// the pair stays framed.
void _focus(CameraRig rig, Vector3 position, SceneTransform? target) {
  if (target == null) {
    rig.target.setValues(
      position.x,
      position.y + cameraFocusHeight,
      position.z,
    );
    return;
  }
  rig.target.setValues(
    position.x + (target.translation.x - position.x) * lockedCameraBias,
    position.y + cameraFocusHeight,
    position.z + (target.translation.z - position.z) * lockedCameraBias,
  );
}

/// Pulls back as the pair separates, so both stay in shot.
double _framingDistance(Vector3 position, SceneTransform? target) {
  if (target == null) return cameraDistance;
  final dx = target.translation.x - position.x;
  final dz = target.translation.z - position.z;
  final separation = math.sqrt(dx * dx + dz * dz);
  return (cameraDistance + separation * lockedDistanceGain).clamp(
    cameraDistance,
    maxLockedCameraDistance,
  );
}

/// Smooths the rig onto the sphere. The opening push-in rides the same
/// smoothing: same desired framing from the first frame, only the rate
/// differs during the intro.
void _ease(CameraRig rig, double distance, double dt) {
  final horizontal = distance * math.cos(rig.pitch);
  final desiredX = rig.target.x - math.sin(rig.yaw) * horizontal;
  // rig.target.y already carries cameraFocusHeight.
  final desiredY = rig.target.y + distance * math.sin(rig.pitch);
  final desiredZ = rig.target.z - math.cos(rig.yaw) * horizontal;

  var sharpness = cameraPositionSharpness;
  if (rig.intro > 0) {
    rig.intro = math.max(0, rig.intro - dt);
    sharpness = introCameraSharpness;
  }
  final blend = 1 - math.exp(-sharpness * dt);
  rig.position.setValues(
    rig.position.x + (desiredX - rig.position.x) * blend,
    rig.position.y + (desiredY - rig.position.y) * blend,
    rig.position.z + (desiredZ - rig.position.z) * blend,
  );
}
