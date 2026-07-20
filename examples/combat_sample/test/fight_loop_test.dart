/// The Phase-3 gate, headless: damage both ways, aggro-token rules (never
/// two simultaneous attackers, stagger returns the token, cooldown before
/// the regrant), the stagger path, and death timing (dying → dissolve
/// clock → despawn, lock released).
library;

import 'dart:math' as math;

import 'package:combat_sample/enemies/enemies.dart';
import 'package:combat_sample/game/camera_rig.dart';
import 'package:combat_sample/game/game_state.dart';
import 'package:combat_sample/game/inputs.dart';
import 'package:combat_sample/game/score.dart';
import 'package:combat_sample/player/player.dart';
import 'package:combat_sample/waves/waves.dart';
import 'package:combat_sample/world/data/resources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import 'support/fight_harness.dart';

int attackersOf(World world) {
  var count = 0;
  world.query<Brawler>(require: const [Enemy]).each((entity, brawler) {
    if (brawler.phase.state == BrawlPhase.telegraph ||
        brawler.phase.state == BrawlPhase.swing) {
      count++;
    }
  });
  return count;
}

Entity? holderInTelegraph(World world) {
  Entity? found;
  world.query<Brawler>(require: const [Enemy]).each((entity, brawler) {
    if (brawler.phase.state == BrawlPhase.telegraph) found = entity;
  });
  return found;
}

void main() {
  test('a light strike lands once for light damage; the edge is one tick '
      'wide', () {
    final game = boot();
    final world = game.world;
    final enemy = world.entitiesWith(require: const [Enemy]).firstOrNull!;
    landPlayerStrike(game, enemy);
    final health = world.get<Health>(enemy);
    expect(health.current, enemyMaxHealth - lightDamage);
    game.pumpFixed(steps: ticksFor(activeSeconds) + 2);
    expect(health.current, enemyMaxHealth - lightDamage,
        reason: 'the active window connects exactly once');
  });

  test('a heavy connect does heavy damage and kicks the camera', () {
    final game = boot();
    final world = game.world;
    final enemy = world.entitiesWith(require: const [Enemy]).firstOrNull!;
    landPlayerStrike(game, enemy, heavy: true);
    expect(world.get<Health>(enemy).current, enemyMaxHealth - heavyDamage);
    expect(world.resource<CameraRig>().kick, greaterThan(0));
  });

  test('the brawl loop damages and staggers the player, and never two '
      'barbarians attack at once', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    final playerHealth = world.get<Health>(player);
    final fighter = world.get<Fighter>(player);

    // Park both barbarians near the idle player and let the loop run.
    var i = 0;
    world.query<SceneTransform>(require: const [Enemy]).each((entity, t) {
      t.translation.setValues(i == 0 ? 0 : 2.5, 0, i == 0 ? 2.4 : 5);
      i++;
    });

    var sawStagger = false;
    for (var tick = 0; tick < 600; tick++) {
      game.pumpFixed(steps: 1);
      expect(attackersOf(world), lessThanOrEqualTo(1),
          reason: 'the token keeps the fight one-at-a-time');
      if (fighter.phase.state == CombatPhase.staggered) sawStagger = true;
    }
    expect(playerHealth.current, lessThan(playerMaxHealth),
        reason: 'swings connect');
    // Poise: an ordinary barbarian swing hurts and shoves but must NOT
    // cancel what the player was doing — only a heavy blow (over
    // `playerPoiseThreshold`) breaks through.
    expect(sawStagger, isFalse,
        reason: 'ordinary swings do not stagger the player');
  });

  test('staggering the holder returns the token, and nobody attacks '
      'through the cooldown', () {
    final game = boot();
    final world = game.world;
    var i = 0;
    world.query<SceneTransform>(require: const [Enemy]).each((entity, t) {
      t.translation.setValues(i == 0 ? 0 : 2.5, 0, i == 0 ? 2.4 : 5);
      i++;
    });

    Entity? holder;
    for (var tick = 0; tick < 300 && holder == null; tick++) {
      game.pumpFixed(steps: 1);
      holder = holderInTelegraph(world);
    }
    expect(holder, isNotNull, reason: 'someone earns the token');

    game.emit(HitLanded(holder!, 10));
    game.pumpFixed(steps: 1); // lands: staggered (+ hitstop)
    expect(world.get<Brawler>(holder).phase.state, BrawlPhase.staggered);
    // Ride out the hit's frozen pumps; the coordinator releases on the
    // next real fixed step.
    game.pumpFixed(steps: 6);
    final coordinator = world.query<AggroCoordinator>().firstOrNull!.$2;
    expect(coordinator.holder, isNull, reason: 'stagger returns the token');

    // Nobody may attack until the cooldown has cooled.
    for (var tick = 0; tick < ticksFor(aggroCooldownSeconds) - 2; tick++) {
      game.pumpFixed(steps: 1);
      expect(attackersOf(world), 0,
          reason: 'the regrant waits out the cooldown');
    }
  });

  test('death: dying runs on the dissolve clock, the lock drops, and the '
      'corpse despawns when it expires', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    final enemy = world.entitiesWith(require: const [Enemy]).firstOrNull!;
    world.get<Health>(enemy).current = 10; // the next strike kills

    // Lock onto it first so the death also releases the lock: park it
    // right in front of the camera — nearest-in-front wins acquisition.
    final playerTransform = world.get<SceneTransform>(player);
    final enemyTransform = world.get<SceneTransform>(enemy);
    final facing = world.get<PlayerMotion>(player).facing;
    enemyTransform.translation.setValues(
      playerTransform.translation.x + math.sin(facing) * 2,
      0,
      playerTransform.translation.z + math.cos(facing) * 2,
    );
    world.resource<CameraRig>().yaw = facing;
    game.emit(const LockPressed());
    game.pumpFixed(steps: 1);
    expect(world.tryGet<Target>(player)?.entity, enemy);

    landPlayerStrike(game, enemy);
    final brawler = world.get<Brawler>(enemy);
    expect(brawler.phase.state, BrawlPhase.dying);
    // One clock covers the fall + corpse delay AND the dissolve window.
    final remaining = world.expiryOf<Dissolving>(enemy);
    expect(remaining, isNotNull, reason: 'the death clock is running');
    expect(
      remaining,
      closeTo(dissolveDelaySeconds + dissolveSeconds, 4 * combatFixedDt),
    );

    // The kill's hitstop freezes a few pumps first; the lock system runs
    // on the next real fixed step.
    game.pumpFixed(steps: 6);
    expect(world.tryGet<Target>(player), isNull, reason: 'death drops the lock');
    expect(world.get<Fighter>(player).stance, Stance.free);

    // The corpse lies through the delay, dissolves, and the death clock
    // expires with the entity — waves own the field now, so a corpse is
    // gone for good and its model slot returns to the pool.
    game.pumpFixed(
      steps: ticksFor(dissolveDelaySeconds + dissolveSeconds) + 8,
    );
    expect(world.tryGet<Health>(enemy), isNull, reason: 'the corpse despawns');
  });

  test('wind gusts by default and calms on a telegraph', () {
    final game = boot();
    final world = game.world;
    final wind = world.resource<WindState>();
    final enemy = world.entitiesWith(require: const [Enemy]).firstOrNull!;

    // No telegraph: the strength eases up to a gust.
    for (var i = 0; i < 24; i++) {
      game.pump();
    }
    final gust = wind.strength;
    expect(gust, greaterThan(1), reason: 'the circling pack gusts');

    // A telegraph holds the breath: the strength eases back down.
    world.get<Brawler>(enemy).phase.go(BrawlPhase.telegraph);
    for (var i = 0; i < 24; i++) {
      game.pump();
    }
    expect(wind.strength, lessThan(gust), reason: 'the telegraph calms it');
  });

  test('restart wipes the field, refields wave 1 and revives the player', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);

    // Kill a barbarian: it pays points. Then the player dies and the world
    // drops into `lost`.
    final enemy = world.entitiesWith(require: const [Enemy]).firstOrNull!;
    world.get<Health>(enemy).current = 5;
    landPlayerStrike(game, enemy);
    expect(world.get<Brawler>(enemy).phase.state, BrawlPhase.dying);
    expect(world.resource<Score>().kills, 1, reason: 'the kill banked');

    world.get<Health>(player).current = 0;
    // `pump` (not `pumpFixed`) runs frame-start + applies state
    // transitions: checkPlayerDeath sets `lost`, then OnEnter(lost) slows.
    game.pump();
    game.pump();
    expect(world.state<GameStatus>(), GameStatus.lost);
    expect(world.clock.timeScale, lessThan(1), reason: 'slow-mo on death');

    // Restart: fighting again, full health, a clean clock, the score and
    // the wave counter back to the start — and wave 1 fielded fresh. The
    // old barbarians were despawned, so these are new entities.
    game.emit(const RestartRequested());
    game.pump();
    game.pump();
    expect(world.state<GameStatus>(), GameStatus.fighting);
    expect(world.clock.timeScale, 1);
    expect(world.get<Health>(player).current, playerMaxHealth);
    expect(world.resource<Score>().kills, 0);
    expect(world.resource<Score>().earned, 0);
    expect(world.resource<WaveState>().wave, 1);
    expect(world.tryGet<Health>(enemy), isNull, reason: 'the old pack is gone');

    var refielded = 0;
    world.query2<Health, Brawler>(require: const [Enemy]).each((
      entity,
      health,
      brawler,
    ) {
      refielded++;
      expect(health.current, enemyMaxHealth);
      expect(brawler.phase.state, isNot(BrawlPhase.dying));
    });
    expect(refielded, enemiesForWave(1));
  });
}
