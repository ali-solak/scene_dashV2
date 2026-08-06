part of '../player.dart';

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

void spawnPlayer(World world) {
  world.spawn(playerBundle());
}

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
    ..velocity.setZero()
    ..rollDirection.setValues(0, 0, 1)
    ..moveIntent.setZero();
  world.remove<Target>(player);
  world.tryGet<Knockback>(player)?.clear();
  world
      .tryGet<SceneTransform>(player)
      ?.translation
      .setValues(playerSpawnX, 0, playerSpawnZ);
  world.tryGet<PlayerAnimator>(player)?.reset();
}

void clearCombatIntents(World world) {
  world.buffer<CombatAction>().clear();
}
