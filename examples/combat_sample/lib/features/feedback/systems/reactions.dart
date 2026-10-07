part of '../feedback.dart';

void installReactions(GameBuilder game) {
  game
    ..addSystem(
      Schedules.fixedUpdate,
      reactToDamage,
      inSet: GameSets.resolution,
      reads: const {Player},
      writes: const {HitFlash, HitPause, Recoil},
    )
    ..addSystem(
      Schedules.fixedUpdate,
      ageRecoil,
      inSet: GameSets.resolution,
      writes: const {Recoil},
      after: const [reactToDamage],
    );
}

void reactToDamage(World world) {
  final player = world.entitiesWith<Player>().firstOrNull;
  for (final hit in world.events<DamageDealt>()) {
    if (!hit.impact || !world.isAlive(hit.target)) continue;
    world.add(hit.target, const HitFlash(), removeAfter: hitFlashSeconds);
    final recoil = world.tryGet<Recoil>(hit.target);
    if (recoil == null) {
      world.add(hit.target, Recoil(hit.direction.clone(), recoilFor(hit)));
    } else {
      recoil.restart(hit.direction, recoilFor(hit));
    }
    final pause = hit.weight == HitWeight.light && !hit.killed
        ? lightHitPauseSeconds
        : hitPauseSeconds;
    world.add(hit.target, const HitPause(), removeAfter: pause);
    if (player != null && player != hit.target) {
      world.add(player, const HitPause(), removeAfter: pause);
    }
  }
}

void ageRecoil(World world) {
  world.query<Recoil>().each((entity, recoil) {
    recoil.age += world.dt;
    if (recoil.age >= recoilSettleSeconds) world.remove<Recoil>(entity);
  });
}
