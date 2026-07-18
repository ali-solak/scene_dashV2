part of '../projectiles.dart';

// Reused scratch so the update loop allocates nothing per projectile.
final Vector3 _projectilePosition = Vector3.zero();
final Vector3 _rockHitPosition = Vector3.zero();

/// OnEnter(playing): decorate the player with a fresh [Blaster] — a
/// feature attaching its component to an entity another feature spawned,
/// with no cross-feature bundle import. Re-adding replaces the previous
/// instance (S4), so every run starts ready; the old blaster-reset call
/// died here. Headless boots have no player and simply skip.
void attachBlaster(World world) {
  final player = world.entitiesWith(require: const [Player]).firstOrNull;
  if (player == null) return;
  world.add(player, Blaster());
}

/// Fires the blaster from the frame's input edges. Edges come from events
/// (consumed once, even across several fixed steps in a frame); the held
/// level comes from the `ButtonInput` resource. Gated to
/// `inState(GameStatus.playing)` at registration; the run-end cleanup
/// lives in [stopBlasterOnRunEnd] on `OnExit`.
void shootProjectiles(World world) {
  final pressed = world.consumeAny<FirePressed>();
  final released = world.consumeAny<FireReleased>();
  final canceled = world.consumeAny<FireCanceled>();

  final player = world
      .query2<Blaster, SceneNode>(require: const [Player])
      .firstOrNull;
  if (player == null) return;
  final (_, blaster, binding) = player;
  final shots = blaster.update(
    pressed: pressed,
    released: released,
    canceled: canceled,
    held: world.buttons<GameAction>().pressed(GameAction.fire),
    dt: world.dt,
  );
  if (shots.isEmpty) return;

  final base = binding.node.globalTransform.getTranslation()
    ..y += playerBodyVisualRadius * 0.45
    ..z -= playerBodyVisualRadius + projectileRadius + 0.08;

  // The bundle itself scopes each shot to the run (DespawnOnExit part).
  final charged = shots.charged;
  if (charged != null) {
    final strength = math.max(charged, minChargedCharge);
    world.spawn(projectileBundle(position: base, charge: strength));
    world.singleOrNull<LockOnReticle>()?.flashFired();
  } else {
    for (var i = 0; i < shots.burst; i++) {
      world.spawn(projectileBundle(position: base));
    }
  }
}

/// Projectiles reset their own state when a run (re)starts; the blaster
/// needs nothing here — [attachBlaster] replaces it with a fresh one, and
/// in-flight impact bursts are run-scoped entities swept by `DespawnOnExit`.
/// The reticle entity is absent headless, hence the null-aware reset.
void resetProjectilesOnRunStart(World world) {
  world.singleOrNull<LockOnReticle>()?.reset();
}

/// Leaving the run aborts any in-flight charge, so the charge VFX cannot
/// linger on the lose screen. The shoot system is gated to
/// `inState(GameStatus.playing)`, so it stops draining fire events here —
/// any held-button edges sent on the lose screen simply expire unread,
/// never firing into it.
void stopBlasterOnRunEnd(World world) {
  world.singleOrNull<Blaster>()?.reset();
}

/// Flies each shot: rock knocks and hit bookkeeping. Lifetime expiry is
/// the bundle's `DespawnAfter`; spatial exits are its `DespawnOutside`.
void updateProjectiles(World world) {
  world.query2<Projectile, SceneNode>().each((entity, projectile, binding) {
    binding.node.globalTranslationInto(_projectilePosition);
    final position = _projectilePosition;
    world.gizmos.sphere(
      position,
      projectileHitRadiusForCharge(projectile.charge),
      color: GizmoColor.blue,
    );

    final hitCount = _knockRocks(world, position, projectile);
    if (hitCount > 0) {
      world.singleOrNull<LockOnReticle>()?.flashImpact();
      if (!projectile.charged ||
          projectile.hitRocks.length >= chargedProjectileMaxHits) {
        world.despawn(entity);
      }
    }
  });
}

/// Applies the native bounce/spin to rocks overlapping [position] and
/// inserts an ECS hit reaction on each resolved rock entity. Returns the
/// hit count.
int _knockRocks(World world, Vector3 position, Projectile projectile) {
  final index = world.resource<SceneNodeIndex>();
  var hitCount = 0;
  world.physics.overlapSphereEntities(
    index,
    position,
    projectileHitRadiusForCharge(projectile.charge),
    layerMask: PhysicsLayers.rock,
    includeFixed: false,
    includeKinematic: false,
    includeDynamic: true,
    includeTriggers: false,
    (entity, hit) {
      if (projectile.charged && projectile.hitRocks.contains(entity)) {
        return true; // already hit this rock; keep scanning the others
      }

      hit.node.globalTranslationInto(_rockHitPosition);
      final xAway = _rockHitPosition.x - position.x;
      final knock = projectileKnockbackForCharge(projectile.charge);
      final lift = projectileLiftForCharge(projectile.charge);
      final spin = projectileSpinForCharge(projectile.charge);
      hit.node.getComponent<RapierRigidBody>()
        ?..linearVelocity = Vector3(
          xAway.clamp(-1, 1).toDouble() * knock * 0.35,
          lift,
          -knock,
        )
        ..angularVelocity = Vector3(-spin, 0, xAway.sign * spin * 0.55);

      if (projectile.charged) projectile.hitRocks.add(entity);
      world.add(
        entity,
        RockHitReaction(strength: projectile.charge.clamp(0.0, 1.0).toDouble()),
        removeAfter: rockHitReactionDuration,
      );
      // Deferred spawn of a run-scoped burst entity — safe inside the scan.
      spawnImpactBurst(world, _rockHitPosition, strength: projectile.charge);
      hitCount++;
      return projectile.charged && hitCount < chargedProjectileMaxHits;
    },
  );
  return hitCount;
}
