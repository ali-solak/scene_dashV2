part of '../damage.dart';

void applyDamage(World world) {
  for (final hit in world.events<DamageDealt>()) {
    final health = world.tryGet<Health>(hit.target);
    if (health == null || health.current <= 0) continue;
    var amount = hit.amount;
    final shield = world.tryGet<Shield>(hit.target);
    if (shield != null) {
      final absorbed = amount.clamp(0.0, shield.current);
      shield
        ..current -= absorbed
        ..sinceHit = 0;
      amount -= absorbed;
    }
    health.current -= amount;
    world.add(hit.target, const HitFlash(), removeAfter: hitFlashSeconds);
  }
}

void destroyDead(World world) {
  world.query2<Health, SceneTransform>().each((entity, health, at) {
    if (health.current > 0) return;
    final bounty = world.tryGet<Bounty>(entity)?.gold ?? 0;
    world.emit(Destroyed(at.translation.clone(), bounty));
    world.despawn(entity);
  });
}

void rechargeShields(World world) {
  world.query<Shield>().each((_, shield) {
    shield.sinceHit += world.dt;
    if (shield.sinceHit < shieldRegenDelay) return;
    shield.current = (shield.current + shieldRegenPerSecond * world.dt).clamp(
      0.0,
      shield.max,
    );
  });
}

void popOnDestroyed(World world) {
  for (final destroyed in world.events<Destroyed>()) {
    world.spawn(popBundle(world, destroyed.at));
  }
}

void animatePops(World world) {
  world.query2<SceneTransform, DespawnAfter>().having<Pop>().each((
    _,
    at,
    life,
  ) {
    at.scale.setValues(1, 1, 1);
    at.scale.scale(popScale * (1 - life.remaining / popSeconds));
  });
}

void showShields(World world) {
  world.query2<Shield, ShieldBubble>().each((_, shield, bubble) {
    final strength = shield.current / shield.max;
    bubble.node.visible = strength > 0;
    bubble.material.baseColorFactor.a = shieldColor.a * strength;
  });
}

void flashOn(World world, Entity entity, HitFlash _) =>
    world.tryGet<Tint>(entity)?.material.emissiveFactor = hitFlashGlow;

void flashOff(World world, Entity entity, HitFlash _) =>
    world.tryGet<Tint>(entity)?.material.emissiveFactor = Vector4.zero();

void attachBubble(World world, Entity entity, Shield _) {
  final node = world.tryGet<NodeRef>(entity)?.node;
  if (node == null) return;
  final bubble = shieldBubble();
  node.add(bubble.node);
  world.add(entity, bubble);
}

void detachBubble(World world, Entity entity, Shield _) {
  final bubble = world.tryGet<ShieldBubble>(entity);
  if (bubble == null) return;
  bubble.node.parent?.remove(bubble.node);
  world.remove<ShieldBubble>(entity);
}
