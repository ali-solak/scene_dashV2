part of '../collectables.dart';

// Reused scratch so per-frame position reads allocate nothing.
final Vector3 _playerScratch = Vector3.zero();
final Vector3 _pickupScratch = Vector3.zero();

/// OnEnter(playing): spawn the pickup spawner — a run-scoped process
/// entity like the rock spawner. Respawning per run *is* the cadence
/// reset, and `DespawnOnExit` sweeps it when the run ends.
void spawnCollectableSpawner(World world) {
  world.spawn([
    const Name('collectable-spawner'),
    CollectableSpawner(),
    const DespawnOnExit(GameStatus.playing),
  ]);
}

/// Spawns a shield pickup when none is active and the cadence is due; the
/// entity query gate is the single source of "is a pickup active".
void spawnShieldPickups(World world) {
  if (world.entitiesWith(require: const [ShieldPickup]).count() > 0) return;
  world.query<CollectableSpawner>().each((entity, spawner) {
    if (!spawner.tick(world.dt)) return;
    // The bundle itself scopes the pickup to the run (DespawnOnExit part).
    world.spawn(shieldPickupBundle(x: spawner.nextLane()));
  });
}

/// Collectables reset their own state when a run (re)starts. The player
/// survives the transition, so any shield carried out of the last run is
/// removed here — the observer pair hides the bubble like on any other
/// removal path.
void resetCollectablesOnRunStart(World world) {
  world.query<Shielded>().each((entity, shielded) {
    world.remove<Shielded>(entity);
  });
  world.resource<ShieldDeflectVfx>().reset();
}

/// Pulses and bobs each pickup's glow child; the physics-driven root
/// transform is left to Rapier.
void animateShieldPickups(World world) {
  final dt = world.dt;
  world
      .query2<ShieldPickupState, ShieldPickupVisuals>(
        require: const [ShieldPickup],
      )
      .each((entity, state, visuals) {
        state.age += dt;
        final pulse = 1 + 0.18 * math.sin(state.age * 6);
        final bob = 0.12 * math.sin(state.age * 3);
        visuals.glow.setLocalUniform(0, bob, 0, pulse);
      });
}

/// Collects a pickup when the player is close enough (a direct squared
/// distance — only zero or one pickup exists). `eachUntil` stops the scan
/// at the first collection: one shield per frame, no further distance
/// checks.
void collectShieldPickups(World world) {
  final player = world.query<SceneNode>(require: const [Player]).firstOrNull;
  if (player == null) return;
  player.$2.node.globalTranslationInto(_playerScratch);
  world.query<SceneNode>(require: const [ShieldPickup]).eachUntil((
    entity,
    binding,
  ) {
    binding.node.globalTranslationInto(_pickupScratch);
    final dx = _pickupScratch.x - _playerScratch.x;
    final dy = _pickupScratch.y - _playerScratch.y;
    final dz = _pickupScratch.z - _playerScratch.z;
    if (dx * dx + dy * dy + dz * dz <= shieldCollectDistanceSq) {
      // The condition is a component on the player: full duration on
      // pickup, and a re-pickup while shielded refreshes the deadline.
      world.add(player.$1, const Shielded(), removeAfter: shieldDuration);
      world.despawn(entity);
      return false; // collected — stop scanning
    }
    return true;
  });
}

/// The bubble and badge follow [Shielded]'s lifecycle: the observer pair
/// (registered in `installCollectables`) flips the target state on every
/// add/remove path — pickup, expiry, run reset — and fires the badge pop.
void shieldGained(World world, Entity entity, Shielded shielded) {
  final v = world.tryGet<PlayerShieldVisuals>(entity);
  if (v == null) return;
  v
    ..shieldActive = true
    ..badgePop = 1;
}

void shieldLost(World world, Entity entity, Shielded shielded) {
  world.tryGet<PlayerShieldVisuals>(entity)?.shieldActive = false;
}

/// Drives the player's shield bubble and activation badge each frame:
/// show/hide eases toward the observer-driven target, the warning flash
/// reads the live `expiryOf` deadline. Mutates player-owned
/// nodes/materials in place.
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

  // Bubble: eased show factor so expiry shrinks it cleanly.
  v.shieldShow = approach(v.shieldShow, v.shieldActive ? 1.0 : 0.0, dt * 8);
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

  // Activation badge: a short overshoot in front of the player.
  v.badgePop = math.max(0, v.badgePop - dt / 0.45);
  final prog = 1 - v.badgePop;
  final badgeScale = v.badgePop > 0.001 ? math.sin(prog * math.pi) * 1.3 : 0.0;
  v.shieldBadge.setLocalUniform(
    0,
    playerBodyVisualRadius * 0.6,
    -(playerBodyVisualRadius + 0.4),
    badgeScale,
  );
}

/// Despawns pickups that fell below the world or rolled past the ramp.
void cleanupPickups(World world) {
  world.query<SceneNode>(require: const [Collectable]).each((entity, binding) {
    binding.node.globalTranslationInto(_pickupScratch);
    if (_pickupScratch.y < collectableKillY ||
        _pickupScratch.z > collectablePassZ) {
      world.despawn(entity);
    }
  });
}

/// Startup: build the shared deflection pool. Gated on the scene at
/// registration (`runIf: hasResource<Scene>()`), so headless boots skip it.
void spawnShieldDeflectVfx(World world) {
  world.resource<ShieldDeflectVfx>().pool = buildDeflectPool()
    ..addTo(world.resource<Scene>());
}

void updateShieldDeflectVfx(World world) {
  final vfx = world.resource<ShieldDeflectVfx>();
  final pool = vfx.pool;
  if (pool == null) return;
  final dt = world.dt;
  final scratch = pool.scratch;
  for (var i = 0; i < vfx.age.length; i++) {
    final a = vfx.age[i];
    if (a >= _deflectDuration) continue;
    final next = a + dt;
    vfx.age[i] = next;
    final t = (next / _deflectDuration).clamp(0.0, 1.0);
    final ease = 1 - math.pow(1 - t, 2).toDouble();
    final fade = 1 - t;
    final s = (0.5 + 1.4 * ease) * fade;
    scratch
      ..setIdentity()
      ..setTranslationRaw(
        vfx.origin[i * 3],
        vfx.origin[i * 3 + 1] + 0.6 * ease,
        vfx.origin[i * 3 + 2],
      )
      ..scaleByDouble(s, s, s, 1);
    pool.mesh.setInstanceTransform(i, scratch);
  }
}
