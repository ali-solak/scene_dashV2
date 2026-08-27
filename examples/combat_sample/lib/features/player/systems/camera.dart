part of '../player.dart';

// Shared scratch, reused each frame.
final Vector3 _boomDir = Vector3.zero();
final Ray _boomRay = Ray.originDirection(Vector3.zero(), Vector3(0, 0, 1));

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
  _retract(world, rig, dt);
  _applyShake(rig, dt);
  aimCombatCamera(rig);
}

/// Pulls the eye in when the ground crosses the boom, so the camera never
/// ends up under the plateau looking up through it.
void _retract(World world, CameraRig rig, double dt) {
  if (!world.hasResource<PhysicsWorld>()) return;
  _boomDir
    ..setFrom(rig.position)
    ..sub(rig.target);
  final reach = _boomDir.length;
  if (reach < 1e-4) return;
  _boomDir.scale(1 / reach);
  _boomRay.origin.setFrom(rig.target);
  _boomRay.direction.setFrom(_boomDir);
  final hit = world.physics.raycast(
    _boomRay,
    maxDistance: reach,
    layerMask: PhysicsLayers.ground,
    includeFixed: true,
    includeKinematic: false,
    includeDynamic: false,
  );
  final allowed = hit == null
      ? reach
      : math.max(hit.distance - cameraCollisionPadding, minBoomLength);
  rig.boom = allowed < rig.boom
      ? allowed
      : smoothTo(rig.boom, allowed, dt, cameraBoomRecoverHalfLife);
  if (rig.boom >= reach) return;
  rig.position
    ..setFrom(rig.target)
    ..addScaled(_boomDir, rig.boom);
}

void _applyShake(CameraRig rig, double dt) {
  if (rig.shake.trauma <= 0) {
    rig.shakeOffset.setIdentity();
    return;
  }
  rig.shakeOffset.setFrom(rig.shake.update(dt).toMatrix4());
}

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
  final desiredX = rig.target.x - math.sin(rig.yaw) * horizontal;
  final desiredY = rig.target.y + distance * math.sin(rig.pitch);
  final desiredZ = rig.target.z - math.cos(rig.yaw) * horizontal;

  var halfLife = cameraPositionHalfLife;
  if (rig.intro > 0) {
    rig.intro = math.max(0, rig.intro - dt);
    halfLife = introCameraHalfLife;
  }
  final blend = smoothBlend(dt, halfLife);
  rig.position.setValues(
    rig.position.x + (desiredX - rig.position.x) * blend,
    rig.position.y + (desiredY - rig.position.y) * blend,
    rig.position.z + (desiredZ - rig.position.z) * blend,
  );
}
