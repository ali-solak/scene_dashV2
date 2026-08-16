part of '../collectables.dart';

// Shared scratch avoids frame allocations.
final Vector3 _playerScratch = Vector3.zero();
final Vector3 _pickupScratch = Vector3.zero();

void spawnShieldPickups(World world) {
  if (world.entitiesWith(require: const [ShieldPickup]).count() > 0) return;
  world.spawn(shieldPickupBundle(x: world.resource<PickupLanes>().nextLane()));
}

void resetCollectablesOnRunStart(World world) {
  world.entitiesWith(require: const [Shielded]).each(world.remove<Shielded>);
}

void animateShieldPickups(World world) {
  final dt = world.dt;
  world.query<ShieldPickupVisuals>(require: const [ShieldPickup]).each((
    entity,
    visuals,
  ) {
    visuals.age += dt;
    final pulse = 1 + 0.18 * math.sin(visuals.age * 6);
    final bob = 0.12 * math.sin(visuals.age * 3);
    visuals.glow.setLocalUniform(0, bob, 0, pulse);
  });
}

void collectShieldPickups(World world) {
  final player = world.query<NodeRef>(require: const [Player]).firstOrNull;
  if (player == null) return;
  player.$2.node.globalTranslationInto(_playerScratch);
  world.query<NodeRef>(require: const [ShieldPickup]).eachUntil((
    entity,
    binding,
  ) {
    binding.node.globalTranslationInto(_pickupScratch);
    final dx = _pickupScratch.x - _playerScratch.x;
    final dy = _pickupScratch.y - _playerScratch.y;
    final dz = _pickupScratch.z - _playerScratch.z;
    if (dx * dx + dy * dy + dz * dz <= shieldCollectDistanceSq) {
      world.add(player.$1, const Shielded(), removeAfter: shieldDuration);
      world.despawn(entity);
      return false;
    }
    return true;
  });
}

void shieldGained(World world, Entity entity, Shielded shielded) {
  world.tryGet<PlayerShieldVisuals>(entity)
    ?..shieldActive = true
    ..badgePop.reset();
}

void shieldLost(World world, Entity entity, Shielded shielded) {
  world.tryGet<PlayerShieldVisuals>(entity)?.shieldActive = false;
}

void updateShieldVisuals(World world) {
  final visuals = world
      .query<PlayerShieldVisuals>(require: const [Player])
      .firstOrNull;
  if (visuals == null) return;
  final v = visuals.$2;
  final remaining = world.expiryOf<Shielded>(visuals.$1);
  final dt = world.dt;

  final warning = remaining != null && remaining <= shieldWarningWindow;
  v.shieldPhase += dt * (warning ? 16 : 4);
  final breathe = 1 + 0.05 * math.sin(v.shieldPhase);
  final warnFlash = warning ? 0.5 + 0.5 * math.sin(v.shieldPhase * 1.5) : 1.0;

  v.shieldShow = smoothTo(
    v.shieldShow,
    v.shieldActive ? 1.0 : 0.0,
    dt,
    shieldShowHalfLife,
  );
  final bubbleScale = v.shieldShow * breathe;
  v.shieldBubble.setLocalUniform(0, 0, 0, bubbleScale);
  v.shieldBubbleMaterial.baseColorFactor = Vector4(
    0.4,
    0.8,
    1.0,
    (0.12 + 0.12 * warnFlash) * v.shieldShow,
  );
  v.shieldBubbleMaterial.emissiveFactor = Vector4(
    0.25 * warnFlash,
    0.6 * warnFlash,
    1.1 * warnFlash,
    1,
  );

  v.badgePop.tick(dt);
  // Up on the way out, the same curve backwards on the way home.
  if (v.badgePop.justFinished && !v.badgePop.reversed) v.badgePop.reverse();
  final badgeScale = v.badgePop.value;
  v.shieldBadge.setLocalUniform(
    0,
    playerBodyVisualRadius * 0.6,
    -(playerBodyVisualRadius + 0.4),
    badgeScale,
  );
}
