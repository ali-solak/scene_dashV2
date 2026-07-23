/// What points buy, headless: the purchase gate, the cooldown gate, and
/// what each skill does to the pack. Skills damage through [HitLanded],
/// so they share the sword's resolution (kills, scoring, knockback).
library;

import 'dart:math' as math;

import 'package:combat_sample/enemies/enemies.dart';
import 'package:combat_sample/game/game_state.dart';
import 'package:combat_sample/game/score.dart';
import 'package:combat_sample/player/player.dart';
import 'package:combat_sample/skills/skills.dart';
import 'package:combat_sample/waves/waves.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import 'support/fight_harness.dart';

double _distance(Vector3 a, Vector3 b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.z - b.z, 2)).toDouble();

/// Buys [skill] UP TO [level] (the menu's job, done directly). Idempotent
/// in the target, not the count: granting level 3 to something already at
/// level 1 buys two, not three.
void grant(TestGame game, Skill skill, {int level = 1}) {
  final book = game.world.resource<SkillBook>();
  while (book.levelOf(skill) < level) {
    game.world.resource<Score>().award(book.priceOf(skill));
    game.emit(SkillUpgradeRequested(skill));
    game.pump();
  }
  expect(book.levelOf(skill), level);
}

/// Pumps [steps] fixed steps holding [enemy] where it stands AND at full
/// health; an interruption test needs a victim that survives long enough
/// to be interrupted.
void pumpUnkillable(TestGame game, Entity enemy, {required int steps}) {
  final world = game.world;
  final spot = world.get<SceneTransform>(enemy).translation.clone();
  for (var i = 0; i < steps; i++) {
    world.get<SceneTransform>(enemy).translation.setFrom(spot);
    world.get<Health>(enemy).current = world.get<Health>(enemy).max;
    game.pumpFixed(steps: 1);
  }
}

/// Pumps up to [maxSteps] fixed steps until [ready], holding the PLAYER
/// at full health. Bounded because hitstop stretches game time; pinned
/// because losing the run stops `castSkills` and its cooldowns.
void pumpUntil(TestGame game, bool Function() ready, {required int maxSteps}) {
  final health = game.world.get<Health>(playerOf(game.world));
  for (var i = 0; i < maxSteps && !ready(); i++) {
    health.current = health.max;
    game.pumpFixed(steps: 1);
  }
}

void main() {
  test('a run starts with nothing bought and nothing castable', () {
    final game = boot();
    final book = game.world.resource<SkillBook>();
    for (final skill in Skill.values) {
      expect(book.isUnlocked(skill), isFalse);
      expect(book.isReady(skill), isFalse);
    }
  });

  test('a skill you cannot afford stays locked and takes no points', () {
    final game = boot();
    final world = game.world;
    world.resource<Score>().award(Skill.fireGush.cost - 1);
    final before = world.resource<Score>().points;

    game.emit(const SkillUpgradeRequested(Skill.fireGush));
    game.pump();

    expect(world.resource<SkillBook>().isUnlocked(Skill.fireGush), isFalse);
    expect(world.resource<Score>().points, before, reason: 'nothing spent');
  });

  test('buying spends the points; the score keeps the run total', () {
    final game = boot();
    final world = game.world;
    final score = world.resource<Score>()..award(500);

    game.emit(const SkillUpgradeRequested(Skill.fireGush));
    game.pump();
    expect(score.points, 500 - Skill.fireGush.cost);
    expect(score.earned, 500, reason: 'spending never lowers the score');

    // Buying again buys the NEXT LEVEL, at the next level's price.
    game.emit(const SkillUpgradeRequested(Skill.fireGush));
    game.pump();
    expect(world.resource<SkillBook>().levelOf(Skill.fireGush), 2);
    expect(score.points, 500 - Skill.fireGush.cost - Skill.fireGush.costAt(1));
  });

  test('levels make a skill heavier, and stop at the cap', () {
    final game = boot();
    final world = game.world;
    final book = world.resource<SkillBook>();

    // Level 1 is the authored damage, exactly.
    grant(game, Skill.fireGush);
    expect(book.powerOf(Skill.fireGush), 1);
    final one = dummyInFront(game, distance: 5);
    final fullOne = world.get<Health>(one).current;
    game.emit(const SkillCast(Skill.fireGush));
    game.pumpFixed(steps: 3);
    final atLevelOne = fullOne - world.get<Health>(one).current;
    expect(atLevelOne, closeTo(fireGushDamage, 1e-6));

    // Take it to the cap and it hits meaningfully harder.
    grant(game, Skill.fireGush, level: maxSkillLevel);
    expect(book.isMaxed(Skill.fireGush), isTrue);
    expect(
      book.powerOf(Skill.fireGush),
      closeTo(1 + skillPowerPerLevel * (maxSkillLevel - 1), 1e-6),
    );

    game.pumpFixed(steps: ticksFor(Skill.fireGush.cooldownSeconds) + 8);
    final two = dummyInFront(game, distance: 5);
    final fullTwo = world.get<Health>(two).current;
    game.emit(const SkillCast(Skill.fireGush));
    game.pumpFixed(steps: 3);
    final atMax = fullTwo - world.get<Health>(two).current;
    expect(atMax, greaterThan(atLevelOne));

    // Capped: further buys are refused and cost nothing.
    final points = (world.resource<Score>()..award(10000)).points;
    game.emit(const SkillUpgradeRequested(Skill.fireGush));
    game.pump();
    expect(book.levelOf(Skill.fireGush), maxSkillLevel);
    expect(world.resource<Score>().points, points);
  });

  test('a burn keeps the damage it was CAST at, not the current level', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.fireGush);
    final enemy = dummyInFront(game, distance: 5);

    game.emit(const SkillCast(Skill.fireGush));
    game.pumpFixed(steps: 3);
    expect(world.get<Burning>(enemy).damage, closeTo(burnTickDamage, 1e-6));

    // Upgrading mid-burn must not retroactively change the fire already
    // on this barbarian.
    grant(game, Skill.fireGush, level: 3);
    expect(world.get<Burning>(enemy).damage, closeTo(burnTickDamage, 1e-6));
  });

  test('an unbought skill does nothing when cast', () {
    final game = boot();
    final enemy = dummyInFront(game);
    final health = game.world.get<Health>(enemy).current;

    game.emit(const SkillCast(Skill.fireGush));
    game.pumpFixed(steps: 4);

    expect(game.world.get<Health>(enemy).current, health);
  });

  test('the fire gush burns the cone and leaves the burn ticking', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.fireGush);
    final enemy = dummyInFront(game, distance: 5);
    final health = world.get<Health>(enemy);
    final full = health.current;

    game.emit(const SkillCast(Skill.fireGush));
    game.pumpFixed(steps: 3);

    expect(health.current, closeTo(full - fireGushDamage, 1e-6));
    expect(world.expiryOf<Burning>(enemy), isNotNull, reason: 'set alight');

    // The burn keeps working after the cone is long gone.
    final afterCone = health.current;
    game.pumpFixed(steps: ticksFor(burnTickSeconds) + 2);
    expect(health.current, lessThan(afterCone));

    // And it ends with its clock rather than burning forever.
    game.pumpFixed(steps: ticksFor(burnSeconds) + 4);
    expect(world.expiryOf<Burning>(enemy), isNull);
    final afterBurn = health.current;
    game.pumpFixed(steps: ticksFor(burnTickSeconds) * 2);
    expect(health.current, afterBurn, reason: 'the fire is out');
  });

  /// DoT ticks land faster than the stagger runs out, so a staggering
  /// tick would stunlock its victim for the whole effect and quietly
  /// make fire gush the best crowd control in the game.
  test('a burn hurts without stunlocking what it is burning', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.fireGush);
    final enemy = dummyInFront(game, distance: 5);

    game.emit(const SkillCast(Skill.fireGush));
    game.pumpFixed(steps: 3);
    expect(world.expiryOf<Burning>(enemy), isNotNull, reason: 'set alight');

    var sawStagger = false;
    for (var i = 0; i < ticksFor(burnSeconds); i++) {
      pumpUnkillable(game, enemy, steps: 1);
      if (world.get<Brawler>(enemy).phase.state == BrawlPhase.staggered) {
        sawStagger = true;
      }
    }

    expect(sawStagger, isFalse, reason: 'the burn never interrupts');
  });

  test('the lava pit sets what stands in it on fire, and the fire tails '
      'off after it leaves', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.lavaPit);
    final enemy = dummyInFront(game, distance: lavaPitDistance);

    game.emit(const SkillCast(Skill.lavaPit));
    game.pumpFixed(steps: 2);
    expect(world.expiryOf<Burning>(enemy), isNull, reason: 'not yet ticked');

    // One lava tick in the pit is enough to light them.
    pumpUnkillable(game, enemy, steps: ticksFor(lavaTickSeconds) + 2);
    expect(
      world.expiryOf<Burning>(enemy),
      isNotNull,
      reason: 'the flame visual is driven off Burning',
    );

    // Out of the pit, the fire goes out on its own clock.
    world
        .get<SceneTransform>(enemy)
        .translation
        .setValues(lavaPitRadius * 6, 0, lavaPitRadius * 6);
    game.pumpFixed(steps: ticksFor(lavaBurnSeconds) + 4);
    expect(world.expiryOf<Burning>(enemy), isNull);
  });

  test('a pit does not downgrade a fire the gush already lit', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.fireGush);
    grant(game, Skill.lavaPit);
    final enemy = dummyInFront(game, distance: lavaPitDistance);

    game.emit(const SkillCast(Skill.fireGush));
    game.pumpFixed(steps: 3);
    expect(world.get<Burning>(enemy).damage, closeTo(burnTickDamage, 1e-6));

    game.emit(const SkillCast(Skill.lavaPit));
    pumpUnkillable(game, enemy, steps: ticksFor(lavaTickSeconds) + 2);

    expect(
      world.get<Burning>(enemy).damage,
      closeTo(burnTickDamage, 1e-6),
      reason: 'the gush burns hotter than the pit; the pit must not win',
    );
  });

  test('lava is area denial, not a stunlock', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.lavaPit);
    final enemy = dummyInFront(game, distance: lavaPitDistance);

    game.emit(const SkillCast(Skill.lavaPit));
    game.pumpFixed(steps: 2);

    var sawStagger = false;
    for (var i = 0; i < ticksFor(lavaTickSeconds * 4); i++) {
      pumpUnkillable(game, enemy, steps: 1);
      if (world.get<Brawler>(enemy).phase.state == BrawlPhase.staggered) {
        sawStagger = true;
      }
    }

    expect(sawStagger, isFalse, reason: 'standing in lava is not a stun');
  });

  test('the fire gush misses what is behind you', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.fireGush);
    final enemy = dummyInFront(game, distance: -4); // straight behind
    final health = world.get<Health>(enemy).current;

    game.emit(const SkillCast(Skill.fireGush));
    game.pumpFixed(steps: 3);

    expect(world.get<Health>(enemy).current, health);
    expect(world.expiryOf<Burning>(enemy), isNull);
  });

  test('a cast goes on cooldown and cannot be spammed', () {
    final game = boot();
    final world = game.world;
    final book = world.resource<SkillBook>();
    grant(game, Skill.fireGush);
    final enemy = dummyInFront(game, distance: 5);

    game.emit(const SkillCast(Skill.fireGush));
    game.pumpFixed(steps: 2);
    expect(book.isReady(Skill.fireGush), isFalse);
    expect(book.readinessOf(Skill.fireGush), lessThan(1));

    // A second cast inside the cooldown does not land its damage.
    final health = world.get<Health>(enemy).current;
    game.emit(const SkillCast(Skill.fireGush));
    game.pumpFixed(steps: 2);
    expect(
      world.get<Health>(enemy).current,
      closeTo(health, burnTickDamage * 2),
      reason: 'only the burn is still ticking, no second gush',
    );

    // Ready again once the cooldown runs out.
    pumpUntil(
      game,
      () => book.isReady(Skill.fireGush),
      maxSteps: ticksFor(Skill.fireGush.cooldownSeconds) * 3,
    );
    expect(book.isReady(Skill.fireGush), isTrue);
    expect(book.readinessOf(Skill.fireGush), 1);
  });

  test('the lava pit outlives the cast and cooks what stands in it', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.lavaPit);

    // Park the dummy exactly where the pit will open.
    final enemy = dummyInFront(game, distance: lavaPitDistance);
    final health = world.get<Health>(enemy);
    final full = health.current;

    game.emit(const SkillCast(Skill.lavaPit));
    game.pumpFixed(steps: 2);
    expect(world.entitiesWith(require: const [LavaPit]).count(), 1);

    // No burst: the pit does its work over time.
    expect(health.current, full);
    pumpHolding(game, enemy, steps: ticksFor(lavaTickSeconds) + 2);
    expect(health.current, closeTo(full - lavaTickDamage, 1e-6));

    // It keeps cooking, then closes on its own clock.
    pumpHolding(game, enemy, steps: ticksFor(lavaTickSeconds * 3));
    expect(health.current, lessThan(full - lavaTickDamage));
    game.pumpFixed(steps: ticksFor(lavaPitSeconds) + 4);
    expect(world.entitiesWith(require: const [LavaPit]).count(), 0);

    final afterClose = health.current;
    game.pumpFixed(steps: ticksFor(lavaTickSeconds) * 3);
    expect(health.current, afterClose, reason: 'the pit is gone');
  });

  test('the lava pit spares whatever stands outside it', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.lavaPit);
    // Well past the pit's rim, but still in front of the player.
    final enemy = dummyInFront(
      game,
      distance: lavaPitDistance + lavaPitRadius * 2,
    );
    final health = world.get<Health>(enemy).current;

    game.emit(const SkillCast(Skill.lavaPit));
    pumpHolding(game, enemy, steps: ticksFor(lavaTickSeconds) * 3);

    expect(world.get<Health>(enemy).current, health);
  });

  test('the wind blast throws the ring off its feet, outward, and the '
      'throw carries', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.windBlast);

    // A ring of barbarians around the player, well inside the blast.
    world.entitiesWith(require: const [Enemy]).each(world.despawn);
    game.pumpFixed(steps: 1);
    final at = world.get<SceneTransform>(playerOf(world)).translation.clone();
    final start = <Entity, double>{};
    for (var i = 0; i < 4; i++) {
      final theta = i * math.pi / 2;
      world.spawn(
        enemyBundle(
          at.x + math.sin(theta) * 3,
          at.z + math.cos(theta) * 3,
          index: i,
        ),
      );
    }
    game.pumpFixed(steps: 1);
    world.query<SceneTransform>(require: const [Enemy]).each((entity, t) {
      start[entity] = _distance(t.translation, at);
    });

    game.emit(const SkillCast(Skill.windBlast));
    // The gust now fires when the cast leap lands, not on the button.
    game.pumpFixed(steps: ticksFor(windCastSeconds) + 4);

    var launched = 0;
    world.query2<Knockback, SceneTransform>(require: const [Enemy]).each((
      entity,
      knockback,
      transform,
    ) {
      expect(knockback.airborne, isTrue, reason: 'off its feet');
      // Thrown outward, not toward the player.
      final outward =
          (transform.translation.x - at.x) * knockback.velocity.x +
          (transform.translation.z - at.z) * knockback.velocity.z;
      expect(outward, greaterThan(0));
      launched++;
    });
    expect(launched, 4);

    // The throw has to CARRY: airborne knockback does not decay, so they
    // land well outside where they stood. Hang time is 2 * lift / gravity,
    // derived so retuning the arc cannot make this assertion vacuous.
    game.pumpFixed(steps: ticksFor(2 * windBlastLift / knockbackGravity) + 8);
    world.query2<Knockback, SceneTransform>(require: const [Enemy]).each((
      entity,
      knockback,
      transform,
    ) {
      expect(knockback.airborne, isFalse, reason: 'landed');
      expect(
        _distance(transform.translation, at),
        greaterThan(start[entity]! + 4),
        reason: 'thrown clear, not dropped where it stood',
      );
    });
  });

  test('a thrown barbarian stays DOWN after it lands', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.windBlast);
    final enemy = dummyInFront(game, distance: 3);

    game.emit(const SkillCast(Skill.windBlast));
    game.pumpFixed(steps: ticksFor(windCastSeconds) + 4); // waits for the leap
    final knockback = world.get<Knockback>(enemy);
    expect(knockback.airborne, isTrue);

    // Ride out the flight. On landing it is still incapacitated; hang
    // time alone let them pop upright the instant they touched the floor.
    game.pumpFixed(steps: ticksFor(2 * windBlastLift / knockbackGravity) + 4);
    expect(knockback.airborne, isFalse, reason: 'landed');
    expect(knockback.incapacitated, isTrue, reason: 'still on the floor');
    expect(
      world.get<Brawler>(enemy).phase.state,
      BrawlPhase.staggered,
      reason: 'and not back to circling or swinging',
    );

    // Then, and only then, it gets up.
    game.pumpFixed(steps: ticksFor(launchDownedSeconds) + 4);
    expect(knockback.incapacitated, isFalse);
  });

  test('the wind blast leaves what is outside its radius alone', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.windBlast);
    final enemy = dummyInFront(game, distance: windBlastRadius + 3);

    game.emit(const SkillCast(Skill.windBlast));
    game.pumpFixed(steps: ticksFor(windCastSeconds) + 4); // waits for the leap

    expect(world.get<Knockback>(enemy).airborne, isFalse);
  });

  // --- Shield ---------------------------------------------------------------

  /// Hits the player for [damage] through the resolution path a barbarian's
  /// swing uses, so the barrier is tested against a real [HitLanded] rather
  /// than against a poke at its own fields.
  void strikePlayer(
    TestGame game, {
    double damage = 20,
    bool heavy = false,
    bool impact = true,
  }) {
    game.emit(
      HitLanded(playerOf(game.world), damage, heavy: heavy, impact: impact),
    );
    // A few steps for resolution to settle. Blows no longer freeze the
    // clock (the hitstop read as lag), so there is no frozen window to
    // pump past; a plain pump is enough.
    game.pumpFixed(steps: 3);
  }

  /// The hand slot's bind-pose frame, read out of `Knight.glb` (both
  /// slots carry it): local +X → rig -X, +Y → rig +Z, +Z → rig +Y.
  Vector3 throughHandSlot(Vector3 local) => Vector3(-local.x, local.z, local.y);

  test('the shield mount stands the slab up and faces it forward', () {
    // Identity is the trap: the shield's face normal is its local +Z, and
    // the slot sends +Z straight up, so an unrotated shield is carried
    // flat like a tray. A yaw cannot fix that; it only spins the tray.
    final flat = throughHandSlot(Vector3(0, 0, 1));
    expect(flat.y, closeTo(1, 1e-6), reason: 'unrotated: face to the sky');

    final face = throughHandSlot(shieldMountRotation.rotated(Vector3(0, 0, 1)));
    final height = throughHandSlot(
      shieldMountRotation.rotated(Vector3(0, 1, 0)),
    );

    // KayKit characters import facing +Z (see characterModelYaw).
    expect(face.z, closeTo(1, 1e-6), reason: 'face points where you look');
    expect(height.y, closeTo(1, 1e-6), reason: 'and the shield is upright');
  });

  test('the shield raises a barrier with charges for its level', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    expect(world.tryGet<Barrier>(player), isNull, reason: 'down to start');

    grant(game, Skill.shield);
    game.emit(const SkillCast(Skill.shield));
    game.pumpFixed(steps: 2);

    final barrier = world.get<Barrier>(player);
    expect(barrier.charges, shieldBaseCharges);
    expect(barrier.maxCharges, shieldBaseCharges);
  });

  test('a raised barrier eats the blow whole: no damage, no shove', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    grant(game, Skill.shield);
    game.emit(const SkillCast(Skill.shield));
    game.pumpFixed(steps: 2);

    final health = world.get<Health>(player);
    final full = health.current;

    strikePlayer(game, damage: 25);

    expect(health.current, full, reason: 'the barrier took it');
    expect(world.get<Barrier>(player).charges, shieldBaseCharges - 1);
    expect(
      world.get<Knockback>(player).velocity.length,
      closeTo(0, 1e-9),
      reason: 'a blocked blow does not shove you either',
    );
  });

  test('the barrier wears down one charge a blow and then breaks', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    grant(game, Skill.shield);
    game.emit(const SkillCast(Skill.shield));
    game.pumpFixed(steps: 2);
    final full = world.get<Health>(player).current;

    // Every charge, spent. A heavy costs exactly what a light costs.
    for (var i = shieldBaseCharges; i > 0; i--) {
      expect(world.get<Barrier>(player).charges, i);
      strikePlayer(game, damage: 20, heavy: i.isEven);
    }

    expect(
      world.tryGet<Barrier>(player),
      isNull,
      reason: 'the last charge takes the barrier with it',
    );
    expect(world.get<Health>(player).current, full, reason: 'none got through');

    // And the next blow is a real one.
    strikePlayer(game, damage: 20);
    expect(world.get<Health>(player).current, closeTo(full - 20, 1e-6));
  });

  test('a level raises the number of blocks, not their weight', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    grant(game, Skill.shield, level: 3);
    game.emit(const SkillCast(Skill.shield));
    game.pumpFixed(steps: 2);

    expect(
      world.get<Barrier>(player).charges,
      shieldChargesFor(3),
      reason: 'base + 2 levels',
    );
  });

  test('the barrier stops blows, not the ground burning under you', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    grant(game, Skill.shield);
    game.emit(const SkillCast(Skill.shield));
    game.pumpFixed(steps: 2);
    final full = world.get<Health>(player).current;

    // A damage-over-time tick: no charge spent, and it lands.
    strikePlayer(game, damage: 6, impact: false);

    expect(
      world.get<Barrier>(player).charges,
      shieldBaseCharges,
      reason: 'ticks do not drain the shield',
    );
    expect(world.get<Health>(player).current, closeTo(full - 6, 1e-6));
  });

  test('a restart takes the barrier down with everything else', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    grant(game, Skill.shield);
    game.emit(const SkillCast(Skill.shield));
    game.pumpFixed(steps: 2);
    expect(world.tryGet<Barrier>(player), isNotNull);

    world.get<Health>(player).current = 0;
    game.pump();
    game.pump();
    // `requestRestart` gates on the state, and the transition it is
    // waiting for only applies on the following frame; restarting
    // before `lost` has landed consumes the event and does nothing.
    expect(world.state<GameStatus>(), GameStatus.lost);

    game.emit(const RestartRequested());
    game.pump();
    game.pump();

    expect(world.tryGet<Barrier>(player), isNull);
  });

  test('a skill kill pays points like any other', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.fireGush);
    final score = world.resource<Score>();
    final kills = score.kills;

    final enemy = dummyInFront(game, distance: 4);
    world.get<Health>(enemy).current = 5; // the gush kills outright

    game.emit(const SkillCast(Skill.fireGush));
    game.pumpFixed(steps: 4);

    expect(world.get<Brawler>(enemy).phase.state, BrawlPhase.dying);
    expect(score.kills, kills + 1);
  });

  test('vitality raises the ceiling and hands over the difference', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    final health = world.get<Health>(player);
    world.resource<Score>().award(1000);

    final max = health.max;
    health.current = max - 40; // hurt, so the grant is visible
    game.emit(const VitalityRequested());
    game.pump();

    expect(world.resource<SkillBook>().vitalityLevel, 1);
    expect(health.max, closeTo(max + vitalityHealthPerLevel, 1e-6));
    expect(
      health.current,
      closeTo(max - 40 + vitalityHealthPerLevel, 1e-6),
      reason: 'the level is granted now, not at the next wave',
    );
  });

  test('vitality costs more each level and stops at the cap', () {
    final game = boot();
    final world = game.world;
    final score = world.resource<Score>()..award(100000);
    final book = world.resource<SkillBook>();

    var spent = 0;
    for (var level = 0; level < maxVitalityLevel; level++) {
      spent += vitalityCost(level);
      game.emit(const VitalityRequested());
      game.pump();
    }
    expect(book.vitalityLevel, maxVitalityLevel);
    expect(score.points, 100000 - spent);
    expect(vitalityCost(1), greaterThan(vitalityCost(0)));

    // Capped: further buys are refused and cost nothing.
    final points = score.points;
    game.emit(const VitalityRequested());
    game.pump();
    expect(book.vitalityLevel, maxVitalityLevel);
    expect(score.points, points);
  });

  test('a restart wipes the book and clears the ground', () {
    final game = boot();
    final world = game.world;
    grant(game, Skill.lavaPit);
    game.emit(const SkillCast(Skill.lavaPit));
    game.pumpFixed(steps: 2);
    expect(world.entitiesWith(require: const [LavaPit]).count(), 1);

    world.get<Health>(playerOf(world)).current = 0;
    game.pump();
    game.pump();
    expect(world.state<GameStatus>(), GameStatus.lost);

    game.emit(const RestartRequested());
    game.pump();
    game.pump();

    final book = world.resource<SkillBook>();
    expect(book.isUnlocked(Skill.lavaPit), isFalse);
    expect(book.vitalityLevel, 0);
    expect(world.entitiesWith(require: const [LavaPit]).count(), 0);
  });

  test('clearing a wave patches the player back up', () {
    final game = boot();
    final world = game.world;
    final health = world.get<Health>(playerOf(world));
    health.current = health.max * 0.3;

    // Wipe the wave and ride out the breather: the next one walks in and
    // the player walks in with it, whole.
    world.entitiesWith(require: const [Enemy]).each(world.despawn);
    game.pumpFixed(steps: ticksFor(waveIntermissionSeconds) + 6);

    expect(world.resource<WaveState>().wave, 2);
    expect(health.current, health.max);
  });
}
