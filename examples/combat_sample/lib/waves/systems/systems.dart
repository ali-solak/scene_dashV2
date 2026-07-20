part of '../waves.dart';

/// The game loop: field a wave, wait until every barbarian is down, take
/// a breather, then field a bigger one. Every few waves one of them
/// arrives as a giant.
///
/// Runs on the update schedule while fighting; the kill payout lives in
/// `rules.applyDamage`, so this system only has to watch the living
/// count and the clock.
void advanceWaves(World world) {
  final waves = world.resource<WaveState>();
  final living = _livingEnemies(world);

  if (waves.engaged && living > 0) return; // the wave is still on its feet

  if (waves.engaged) {
    // Cleared: take a breather before the next one walks in.
    waves.engaged = false;
    waves.intermission = waveIntermissionSeconds;
    return;
  }

  if (waves.inIntermission) {
    waves.intermission -= world.dt;
    if (waves.intermission > 0) return;
    waves.intermission = 0;
  }

  waves.wave += 1;
  waves.engaged = true;
  _healPlayer(world);
  _fieldWave(world, waves.wave);
}

/// The breather's reward: surviving a wave patches you up before the next
/// one walks in. Without it the run is decided by the chip damage of wave
/// 2, not by the fight.
void _healPlayer(World world) {
  world.query<Health>(require: const [Player]).each((entity, health) {
    health.heal(health.max * waveHealFraction);
  });
}

/// Barbarians still standing (a corpse mid-dissolve does not count — the
/// next wave should not wait on the ragdoll).
int _livingEnemies(World world) {
  var living = 0;
  world.query2<Brawler, Health>(require: const [Enemy]).each((
    entity,
    brawler,
    health,
  ) {
    if (health.alive && brawler.phase.state != BrawlPhase.dying) living++;
  });
  return living;
}

/// Spawns [wave]'s barbarians evenly around the ring, scaled for the
/// wave, with one giant on the giant waves.
void _fieldWave(World world, int wave) {
  final count = enemiesForWave(wave);
  final health = healthForWave(wave);
  final power = powerForWave(wave);
  final giantIndex = waveHasGiant(wave) ? wave % count : -1;

  for (var i = 0; i < count; i++) {
    final theta = (i + 0.5) * (2 * math.pi / count) + wave * 0.6;
    final giant = i == giantIndex;
    final entity = world.spawn(
      enemyBundle(
        math.sin(theta) * waveSpawnRadius,
        math.cos(theta) * waveSpawnRadius,
        index: i,
        health: giant ? health * giantHealthFactor : health,
        power: giant ? power * giantPower : power,
        giant: giant,
      ),
    );
    // The giant walks in normal-sized and swells on the transform clip.
    if (giant) {
      world.add(entity, const Transforming(),
          removeAfter: giantTransformSeconds);
    }
  }
}

/// `OnEnter(fighting)` (boot and every restart), called by rules'
/// `startRun`: clear the field and start the run at wave 1.
void resetWaves(World world) {
  world.resource<WaveState>().reset();
  world.resource<Score>().reset();
  world.entitiesWith(require: const [Enemy]).each(world.despawn);
}
