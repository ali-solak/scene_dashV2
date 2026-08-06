part of '../projectiles.dart';

// Shared scratch avoids frame allocations.
final Vector3 _projectilePosition = Vector3.zero();
final Vector3 _rockHitPosition = Vector3.zero();

void attachBlaster(World world) {
  final player = world.entitiesWith(require: const [Player]).firstOrNull;
  if (player == null) return;
  world.add(player, Blaster());
}

void shootProjectiles(World world) {
  final pressed = world.consumeAny<FirePressed>();
  final released = world.consumeAny<FireReleased>();
  final canceled = world.consumeAny<FireCanceled>();

  final player = world
      .query2<Blaster, NodeRef>(require: const [Player])
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

void resetProjectilesOnRunStart(World world) {
  world.singleOrNull<LockOnReticle>()?.reset();
}

void stopBlasterOnRunEnd(World world) {
  world.singleOrNull<Blaster>()?.reset();
}

void updateProjectiles(World world) {
  world.query2<Projectile, NodeRef>().each((entity, projectile, binding) {
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
        return true;
      }

      hit.node.globalTranslationInto(_rockHitPosition);
      final xAway = _rockHitPosition.x - position.x;
      final knock = projectileKnockbackForCharge(projectile.charge);
      final lift = projectileLiftForCharge(projectile.charge);
      final spin = projectileSpinForCharge(projectile.charge);
      hit.node.getComponent<RigidBody>()
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
      spawnImpactBurst(world, _rockHitPosition, strength: projectile.charge);
      hitCount++;
      return projectile.charged && hitCount < chargedProjectileMaxHits;
    },
  );
  return hitCount;
}
