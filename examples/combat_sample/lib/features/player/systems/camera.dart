part of '../player.dart';

// Shared scratch, reused each frame.
final Vector3 _shakeForward = Vector3.zero();
final Vector3 _shakeRight = Vector3.zero();
final Vector3 _shakeUp = Vector3.zero();
final Vector3 _shakeAim = Vector3.zero();
final Vector3 _shakeWorldUp = Vector3(0, 1, 0);

void installPlayerCamera(GameBuilder game) {
  game
    ..addSystem(
      Schedules.startup,
      mountCamera,
      reads: const {},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      updateCameraRig,
      inSet: GameSets.resolution,
      reads: const {Player, PlayerMotion, SceneTransform, Target},
    );
}

void mountCamera(World world) => mountCombatCamera(world.resource<Scene>());

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
    _applyShake(rig, dt);
    aimCombatCamera(rig);
    return;
  }

  for (final hit in world.events<HitLanded>()) {
    if (!hit.impact) continue;
    rig.shake.addTrauma(hit.heavy ? heavyHitTrauma : lightHitTrauma);
  }

  final position = transform.translation;
  final target = _targetTransform(world, player);
  _aim(rig, world.resource<LookInput>(), position, target, dt);
  _focus(rig, position, target);
  _ease(rig, _framingDistance(position, target), dt);
  _applyShake(rig, dt);
  aimCombatCamera(rig);
}

/// Publishes the boom's vectors with this frame's shake folded in. The
/// translation rides the camera's own axes so a jolt reads as the camera
/// being knocked, not the world sliding.
void _applyShake(CameraRig rig, double dt) {
  rig.position.setFrom(rig.basePosition);
  rig.target.setFrom(rig.baseTarget);
  if (rig.shake.trauma <= 0) return;

  final offset = rig.shake.update(dt);
  _shakeForward
    ..setFrom(rig.baseTarget)
    ..sub(rig.basePosition);
  final reach = _shakeForward.length;
  if (reach < 1e-6) return;
  _shakeForward.scale(1 / reach);
  _shakeRight
    ..setFrom(_shakeWorldUp)
    ..crossInto(_shakeForward, _shakeRight);
  if (_shakeRight.length2 < 1e-12) return;
  _shakeRight.normalize();
  _shakeUp
    ..setFrom(_shakeForward)
    ..crossInto(_shakeRight, _shakeUp);

  rig.position
    ..addScaled(_shakeRight, offset.translation.x)
    ..addScaled(_shakeUp, offset.translation.y)
    ..addScaled(_shakeForward, offset.translation.z);

  // Pitch about the camera's right, not its forward, which would roll.
  _shakeAim
    ..setFrom(_shakeForward)
    ..applyAxisAngle(_shakeWorldUp, offset.rotationEuler.y)
    ..applyAxisAngle(_shakeRight, offset.rotationEuler.x);
  rig.target
    ..setFrom(rig.position)
    ..addScaled(_shakeAim, reach);
}

void _orbitTitle(CameraRig rig, double dt) {
  rig
    ..yaw += titleOrbitRate * dt
    ..pitch = titleCameraPitch;
  rig.baseTarget.setValues(0, cameraFocusHeight, 0);
  final horizontal = titleCameraDistance * math.cos(rig.pitch);
  rig.basePosition.setValues(
    rig.baseTarget.x - math.sin(rig.yaw) * horizontal,
    rig.baseTarget.y + titleCameraDistance * math.sin(rig.pitch),
    rig.baseTarget.z - math.cos(rig.yaw) * horizontal,
  );
}

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
  // Locked framing discards manual look.
  look.takeYawDelta();
  look.takePitchDelta();
  final desiredYaw = math.atan2(
    target.translation.x - position.x,
    target.translation.z - position.z,
  );
  // Yaw wraps, so it needs the blend factor rather than smoothTo: the gap is
  // the shortest arc, not plain subtraction.
  rig.yaw +=
      angleDifference(desiredYaw, rig.yaw) *
      smoothBlend(dt, cameraYawHalfLife);
  rig.pitch = smoothTo(rig.pitch, cameraLockedPitch, dt, cameraPitchHalfLife);
}

void _focus(CameraRig rig, Vector3 position, SceneTransform? target) {
  if (target == null) {
    rig.baseTarget.setValues(
      position.x,
      position.y + cameraFocusHeight,
      position.z,
    );
    return;
  }
  rig.baseTarget.setValues(
    position.x + (target.translation.x - position.x) * lockedCameraBias,
    position.y + cameraFocusHeight,
    position.z + (target.translation.z - position.z) * lockedCameraBias,
  );
}

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

void _ease(CameraRig rig, double distance, double dt) {
  final horizontal = distance * math.cos(rig.pitch);
  final desiredX = rig.baseTarget.x - math.sin(rig.yaw) * horizontal;
  final desiredY = rig.baseTarget.y + distance * math.sin(rig.pitch);
  final desiredZ = rig.baseTarget.z - math.cos(rig.yaw) * horizontal;

  var halfLife = cameraPositionHalfLife;
  if (rig.intro > 0) {
    rig.intro = math.max(0, rig.intro - dt);
    halfLife = introCameraHalfLife;
  }
  final blend = smoothBlend(dt, halfLife);
  rig.basePosition.setValues(
    rig.basePosition.x + (desiredX - rig.basePosition.x) * blend,
    rig.basePosition.y + (desiredY - rig.basePosition.y) * blend,
    rig.basePosition.z + (desiredZ - rig.basePosition.z) * blend,
  );
}
