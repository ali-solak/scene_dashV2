/// Tasks 9 + 10, headless: stance vectors (camera-relative free move,
/// strafe-set locked move, back-off walk, rooted actions, roll
/// displacement, arena clamp) and the lock-on lifecycle (acquire in
/// range + cone, cycle sorted by angle, release on press-again / death /
/// range break). Boots the FULL feature set under strictAccess — this
/// suite doubles as the whole-game conflict-detector proof.
library;

import 'dart:math' as math;

import 'package:combat_sample/enemies/enemies.dart';
import 'package:combat_sample/game/camera_rig.dart';
import 'package:combat_sample/game/game_state.dart';
import 'package:combat_sample/game/inputs.dart';
import 'package:combat_sample/game/sets.dart';
import 'package:combat_sample/player/player.dart';
import 'package:combat_sample/world/data/assets.dart';
import 'package:combat_sample/rules/rules.dart';
import 'package:combat_sample/skills/skills.dart';
import 'package:combat_sample/waves/waves.dart';
import 'package:combat_sample/world/data/config.dart' show arenaBoundsRadius;
import 'package:combat_sample/world/world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

const double dt = combatFixedDt;

/// Boots the full feature set. This suite pins stance and lock semantics,
/// so the aggro coordinator is despawned — barbarians approach and circle
/// but never earn the token, keeping the player untouched and the runs
/// deterministic (the fight loop has its own suite).
TestGame boot() {
  final game = TestGame.headless(
    fixedDt: combatFixedDt,
    strictAccess: true,
    features: [
      (game) {
        game
          ..addState<GameStatus>(GameStatus.fighting)
          ..configureSets(Schedules.fixedUpdate, [
            GameSets.movement,
            GameSets.enemyMovement,
            GameSets.actions,
            GameSets.resolution,
            GameSets.waves,
          ])
          ..configureSets(Schedules.update, [GameSets.logic])
          ..world.insert(ButtonInput<CombatAction>())
          ..world.insert(AxisInput<MoveAxis>())
          ..world.insert(InputBuffer<CombatAction>(window: bufferWindow))
          ..world.insert(LookInput())
          ..world.insert(CameraRig());
      },
      installWorld(WorldAssets.none()),
      installPlayer,
      installEnemies,
      installWaves,
      installSkills,
      installRules,
    ],
  );
  game.start();
  // Event readers register lazily; one boot frame before any emit.
  game.pumpFixed(steps: 1);
  final coordinator = game.world.query<AggroCoordinator>().firstOrNull;
  if (coordinator != null) {
    game.world.despawn(coordinator.$1);
    game.pumpFixed(steps: 1);
  }
  // Wave 1 fields its barbarians on a ring; this suite pins stance and
  // lock behaviour against known spots, so place them deterministically.
  placeEnemies(game.world, const [(-3.0, -2.0), (4.0, 1.5)]);
  return game;
}

/// Puts the wave's barbarians at [spots], in query order.
void placeEnemies(World world, List<(double, double)> spots) {
  var i = 0;
  world.query<SceneTransform>(require: const [Enemy]).each((entity, t) {
    if (i >= spots.length) return;
    t.translation.setValues(spots[i].$1, 0, spots[i].$2);
    i++;
  });
  expect(i, spots.length, reason: 'wave 1 fielded \${spots.length}');
}

Entity playerOf(World world) =>
    world.entitiesWith(require: const [Player]).firstOrNull!;

/// The enemy nearest to (x, z) — spawn spots drift once the brawl
/// machines start walking, so lookups are proximity-based.
Entity enemyAt(World world, double x, double z) {
  Entity? found;
  var best = double.infinity;
  world.query<SceneTransform>(require: const [Enemy]).each((entity, t) {
    final dx = t.translation.x - x;
    final dz = t.translation.z - z;
    final d = dx * dx + dz * dz;
    if (d < best) {
      best = d;
      found = entity;
    }
  });
  expect(best, lessThan(2.25), reason: 'nearest enemy drifted too far');
  return found!;
}

void main() {
  test('the full feature set boots clean under strictAccess and spawns '
      'the player and both dummies headless', () {
    final game = boot();
    final world = game.world;
    expect(world.entitiesWith(require: const [Player]).count(), 1);
    expect(
      world.entitiesWith(require: const [Enemy]).count(),
      enemiesForWave(1),
    );
    expect(world.state<GameStatus>(), GameStatus.fighting);
  });

  test('free stance: input is camera-relative and facing turns toward '
      'velocity', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    final transform = world.get<SceneTransform>(player);
    final motion = world.get<PlayerMotion>(player);
    final z0 = transform.translation.z;

    // Rig yaw 0: camera forward is +Z, so W moves +Z by exactly one step.
    world.resource<CameraRig>().yaw = 0;
    world.axes<MoveAxis>().setValue(MoveAxis.y, 1);
    game.pumpFixed(steps: 1);
    // 1e-5: SceneTransform stores 32-bit floats.
    expect(transform.translation.z - z0, closeTo(freeMoveSpeed * dt, 1e-5));
    expect(transform.translation.x, closeTo(0, 1e-5));

    // Facing was pi (spawn, the exact antipode of the +Z heading — either
    // arc is shortest); it closes on the heading at the configured rate,
    // not instantly.
    var distance = (motion.facing - 0).abs() % (2 * math.pi);
    if (distance > math.pi) distance = 2 * math.pi - distance;
    expect(distance, closeTo(math.pi - turnRate * dt, 1e-6));
  });

  test('lock-on acquires the nearest living enemy in range and cone', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    game.emit(const LockPressed());
    game.pumpFixed(steps: 1);

    final near = enemyAt(world, 4, 1.5); // 5.3 u vs 7.6 u away
    expect(world.tryGet<Target>(player)?.entity, near);
    expect(world.get<Fighter>(player).stance, Stance.locked);
  });

  test('cycle switches by angle and wraps; press-again toggles the lock '
      'off', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    final near = enemyAt(world, 4, 1.5);
    final far = enemyAt(world, -3, -2);

    game.emit(const LockPressed());
    game.pumpFixed(steps: 1);
    expect(world.tryGet<Target>(player)?.entity, near);

    game.emit(const LockCycled());
    game.pumpFixed(steps: 1);
    expect(world.tryGet<Target>(player)?.entity, far, reason: 'cycled');

    game.emit(const LockCycled());
    game.pumpFixed(steps: 1);
    expect(world.tryGet<Target>(player)?.entity, near, reason: 'wrapped');

    // The lock button is a toggle: press-again releases immediately.
    game.emit(const LockPressed());
    game.pumpFixed(steps: 1);
    expect(world.tryGet<Target>(player), isNull);
    expect(world.get<Fighter>(player).stance, Stance.free);
  });

  test('the lock drops itself on target death and on range break', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    final near = enemyAt(world, 4, 1.5);

    game.emit(const LockPressed());
    game.pumpFixed(steps: 1);
    expect(world.tryGet<Target>(player)?.entity, near);

    world.get<Health>(near).current = 0;
    game.pumpFixed(steps: 1);
    expect(world.tryGet<Target>(player), isNull, reason: 'death releases');
    expect(world.get<Fighter>(player).stance, Stance.free);

    // Re-acquire: the camera cone misses both (yaw 0 looks away), so the
    // nearest-in-range fallback picks the one still living.
    final far = enemyAt(world, -3, -2);
    game.emit(const LockPressed());
    game.pumpFixed(steps: 1);
    expect(world.tryGet<Target>(player)?.entity, far);
    // The far rim: enemy movement clamps to the arena, so "out of range"
    // must still be a legal arena position (18 u from the player > break).
    world.get<SceneTransform>(far).translation.setValues(0, 0, -13);
    game.pumpFixed(steps: 1);
    expect(world.tryGet<Target>(player), isNull, reason: 'range break');
  });

  test('locked stance: faces the target, strafe speed toward vs the '
      'back-off walk away', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    final transform = world.get<SceneTransform>(player);
    final motion = world.get<PlayerMotion>(player);
    final rig = world.resource<CameraRig>();

    game.emit(const LockPressed());
    game.pumpFixed(steps: 1);
    game.pumpFixed(steps: 1); // movement sees the flushed Target
    final near = world.tryGet<Target>(playerOf(world))!.entity;
    final nearTransform = world.get<SceneTransform>(near);
    double toTarget() => math.atan2(
      nearTransform.translation.x - transform.translation.x,
      nearTransform.translation.z - transform.translation.z,
    );
    // 0.15 rad: the target circles between the facing write and this read.
    expect(motion.facing, closeTo(toTarget(), 0.15));

    // Aim the camera straight at the target, then W approaches at locked
    // speed and S backs off slower — the strafe set.
    rig.yaw = toTarget();
    world.axes<MoveAxis>().setValue(MoveAxis.y, 1);
    game.pumpFixed(steps: 1);
    expect(motion.velocity.length, closeTo(lockedMoveSpeed, 1e-6));

    rig.yaw = toTarget();
    world.axes<MoveAxis>().setValue(MoveAxis.y, -1);
    game.pumpFixed(steps: 1);
    expect(
      motion.velocity.length,
      closeTo(lockedMoveSpeed * backpedalFactor, 1e-6),
    );
  });

  test('actions root the fighter; a roll commits its direction and covers '
      'roll speed for the roll duration', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    final transform = world.get<SceneTransform>(player);
    final fighter = world.get<Fighter>(player);

    // Rooted during startup: W held, but a strike is winding up.
    world.resource<CameraRig>().yaw = 0;
    world.axes<MoveAxis>().setValue(MoveAxis.y, 1);
    world.buffer<CombatAction>().record(CombatAction.attack);
    game.pumpFixed(steps: 1); // movement (idle) then startup entered
    final zAtStartup = transform.translation.z;
    game.pumpFixed(steps: 5);
    expect(fighter.phase.state, CombatPhase.startup);
    // Committing, not frozen: the windup keeps a fraction of the drift,
    // so it moves — but well under a free step.
    final windupDrift = transform.translation.z - zAtStartup;
    final freeDrift = freeMoveSpeed * dt * 5;
    expect(windupDrift, greaterThan(0), reason: 'not fully rooted');
    expect(windupDrift, lessThan(freeDrift * 0.6), reason: 'but committing');

    // Ride the whole swing back to idle, then roll: displacement ≈
    // speed × duration.
    world.axes<MoveAxis>().setValue(MoveAxis.y, 0);
    game.pumpFixed(
      steps:
          ticksFor(startupSeconds) +
          ticksFor(activeSeconds) +
          ticksFor(recoverySeconds) +
          4,
    );
    expect(fighter.phase.state, CombatPhase.idle);
    world.axes<MoveAxis>().setValue(MoveAxis.y, 1);
    world.buffer<CombatAction>().record(CombatAction.roll);
    game.pumpFixed(steps: 1); // roll consumed: rolling entered
    expect(fighter.phase.state, CombatPhase.rolling);
    final startX = transform.translation.x;
    final startZ = transform.translation.z;
    game.pumpFixed(steps: 1); // direction committed, first roll step
    world.axes<MoveAxis>().setValue(MoveAxis.y, 0);
    var rollMoveTicks = 1;
    while (fighter.phase.state == CombatPhase.rolling) {
      game.pumpFixed(steps: 1);
      rollMoveTicks++;
    }
    // The machine serves the full roll; movement rides one tick behind it
    // (measure magnitude — the committed direction is camera-relative).
    expect(rollMoveTicks, ticksFor(rollSeconds));
    final dx = transform.translation.x - startX;
    final dz = transform.translation.z - startZ;
    expect(
      math.sqrt(dx * dx + dz * dz),
      closeTo(rollSpeed * rollMoveTicks * dt, rollSpeed * dt * 2 + 1e-6),
    );
  });

  test('the dash goes where you are MOVING, not where you are facing', () {
    final game = boot();
    final world = game.world;
    final player = playerOf(world);
    final transform = world.get<SceneTransform>(player);
    final fighter = world.get<Fighter>(player);

    // Spawn facing is pi (-Z). Move hard +X (camera yaw 0 → x input is
    // world +X) so the dash direction and the facing disagree.
    world.resource<CameraRig>().yaw = 0;
    world.axes<MoveAxis>().setValue(MoveAxis.x, 1);
    game.pumpFixed(steps: 1);

    final startX = transform.translation.x;
    final startZ = transform.translation.z;
    world.buffer<CombatAction>().record(CombatAction.roll);
    var guard = 0;
    while (fighter.phase.state != CombatPhase.rolling && guard++ < 30) {
      world.resource<CameraRig>().yaw = 0;
      game.pumpFixed(steps: 1);
    }
    expect(fighter.phase.state, CombatPhase.rolling, reason: 'roll fired');
    while (fighter.phase.state == CombatPhase.rolling && guard++ < 120) {
      world.resource<CameraRig>().yaw = 0;
      game.pumpFixed(steps: 1);
    }

    final dx = transform.translation.x - startX;
    final dz = transform.translation.z - startZ;
    expect(dx, greaterThan(1.5), reason: 'dashed along the input (+X)');
    expect(dx.abs(), greaterThan(dz.abs() * 3), reason: 'not along the facing');
  });

  test('the arena clamp holds the fighter inside the bounds radius', () {
    final game = boot();
    final world = game.world;
    final transform = world.get<SceneTransform>(playerOf(world));
    world.resource<CameraRig>().yaw = 0;
    world.axes<MoveAxis>().setValue(MoveAxis.y, 1);
    for (var i = 0; i < 400; i++) {
      world.resource<CameraRig>().yaw = 0; // pin camera-relative +Z
      game.pumpFixed(steps: 1);
    }
    final r = math.sqrt(
      transform.translation.x * transform.translation.x +
          transform.translation.z * transform.translation.z,
    );
    expect(r, lessThanOrEqualTo(arenaBoundsRadius + 1e-4));
  });
}

int ticksFor(double seconds) {
  var t = 0.0;
  var n = 0;
  while (t < seconds) {
    t += combatFixedDt;
    n++;
  }
  return n;
}
