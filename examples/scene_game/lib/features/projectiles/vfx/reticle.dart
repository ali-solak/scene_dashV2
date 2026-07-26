part of '../projectiles.dart';

// Reused scratch so the per-frame targeting pass allocates nothing.
final Vector3 _reticlePlayerPos = Vector3.zero();

/// Startup: spawn the single reused reticle as a process entity — the
/// mount adapter parents its node at the scene root. Gated on the scene at
/// registration (`runIf: hasResource<Scene>()`), so headless boots skip it
/// and never carry a reticle.
void spawnLockOnReticle(World world) {
  final model = ReticleModel();
  final component = WidgetComponent(
    child: ReticleWidget(model),
    size: const Size.square(reticleCanvas),
    worldHeight: rockRadius * 4.4,
    pixelRatio: 1.5,
    input: WidgetInput.manual,
    update: WidgetUpdatePolicy.everyFrame,
  );
  final node = Node()
    ..frustumCulled = false
    ..addComponent(component);
  world.spawn([
    const Name('lock-on-reticle'),
    SceneNode(node),
    LockOnReticle(node: node, model: model)..hideNode(),
  ]);
}

/// `observe<LockOnReticle>` onRemove: the model dies with the component on
/// any removal path. No gameplay path despawns the reticle today; the
/// observer is the doctrine, [disposeLockOnReticle] the shutdown reality.
void disposeReticleModel(World world, Entity entity, LockOnReticle reticle) =>
    reticle.dispose();

/// Shutdown: entities are not despawned at shutdown (only resources are
/// disposed), so the reticle's model is closed here explicitly. A reticle
/// already despawned earlier leaves the store empty — no double dispose.
void disposeLockOnReticle(World world) {
  world.singleOrNull<LockOnReticle>()?.dispose();
}

/// Drives the reticle onto the most relevant rock in the firing lane,
/// facing the camera. Visual feedback only — no homing.
void updateLockOnReticle(World world) {
  final reticle = world.singleOrNull<LockOnReticle>();
  final blaster = world.singleOrNull<Blaster>();
  if (reticle == null || blaster == null) return;
  final camera = world.resource<CameraRig>();
  final dt = world.dt;
  reticle.firedFlash = math.max(0, reticle.firedFlash - dt / 0.25);
  reticle.impactFlash = math.max(0, reticle.impactFlash - dt / 0.3);

  final player = world.query<SceneNode>(require: const [Player]).firstOrNull;
  if (player == null) return;
  player.$2.node.globalTranslationInto(_reticlePlayerPos);
  final pos = _reticlePlayerPos;

  // Nearest rock ahead of the player within the firing lane.
  var bestZ = -1e9;
  var hasRock = false;
  var bx = 0.0, by = 0.0, bz = 0.0;
  world.query<SceneNode>(require: const [Rock]).each((entity, binding) {
    final m = binding.node.globalTransform.storage;
    final rx = m[12], ry = m[13], rz = m[14];
    if (rz > pos.z + 1.0) return;
    if ((rx - pos.x).abs() > reticleLaneHalfWidth) return;
    if (rz > bestZ) {
      bestZ = rz;
      hasRock = true;
      bx = rx;
      by = ry;
      bz = rz;
    }
  });

  final charging = blaster.isCharging;
  final showing =
      hasRock &&
      (charging || reticle.firedFlash > 0.01 || reticle.impactFlash > 0.01);
  reticle.opacity = approach(reticle.opacity, showing ? 1.0 : 0.0, dt * 10);
  reticle.charge01 = approach(
    reticle.charge01,
    charging ? blaster.charge01 : 0.0,
    dt * 12,
  );
  reticle.locked = charging && blaster.charge01 >= 0.98;
  reticle.pushToModel();

  if (reticle.opacity > 0.01 && hasRock) {
    reticle.billboardAt(bx, by, bz, camera.position);
  } else {
    reticle.hideNode();
  }
}
