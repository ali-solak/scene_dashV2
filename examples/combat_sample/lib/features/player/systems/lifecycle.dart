part of '../player.dart';

/// Spawn, per-run reset, and the intent flush on leaving the fight.
void installPlayerLifecycle(GameBuilder game) {
  game
    ..addSystem(
      Schedules.startup,
      spawnPlayer,
      writes: const {Player, Fighter, PlayerMotion},
    )
    ..addSystem(
      OnEnter(GameStatus.fighting),
      resetPlayerRun,
      reads: const {Player},
      writes: const {
        Fighter,
        PlayerMotion,
        PlayerAnimator,
        Target,
        Health,
        Knockback,
        SceneTransform,
      },
      runIf: freshRun,
    )
    ..addSystem(
      OnExit(GameStatus.fighting),
      clearCombatIntents,
      reads: const {},
    );
}

/// Spawns the player data.
void spawnPlayer(World world) {
  world.spawn(playerBundle());
}

/// Resets the player to a clean, full-health idle at the spawn mark.
/// `OnEnter(fighting)` behind [freshRun]: boot, title start and restart —
/// never a menu-close resume.
void resetPlayerRun(World world) {
  final row = world
      .query3<Fighter, PlayerMotion, Health>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (player, fighter, motion, health) = row;
  health.current = health.max;
  fighter.phase.go(CombatPhase.idle);
  fighter
    ..heavy = false
    ..stance = Stance.free
    ..sinceHurt = double.infinity;
  motion
    ..facing = math.pi
    ..velocity.setZero();
  motion.rollDirection.setValues(0, 0, 1);
  motion.moveIntent.setZero();
  world.remove<Target>(player);
  world.tryGet<Knockback>(player)?.clear();
  world
      .tryGet<SceneTransform>(player)
      ?.translation
      .setValues(playerSpawnX, 0, playerSpawnZ);
  world.tryGet<PlayerAnimator>(player)?.reset();
}

/// Clears buffered combat actions when leaving a fight.
void clearCombatIntents(World world) {
  world.buffer<CombatAction>().clear();
}
