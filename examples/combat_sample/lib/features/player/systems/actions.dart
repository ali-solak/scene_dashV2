part of '../player.dart';

void installPlayerActions(GameBuilder game) {
  game
    ..addSystem(
      Schedules.fixedUpdate,
      fighterDriver,
      inSet: GameSets.actions,
      writes: const {Fighter},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      announceWindup,
      inSet: GameSets.actions,
      reads: const {Player, Fighter, PlayerMotion},
      after: const [fighterDriver],
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      spawnPlayerFx,
      inSet: GameSets.actions,
      reads: const {Player, Fighter, PlayerMotion, SceneTransform},
      after: const [fighterDriver],
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      updateBladeTrail,
      inSet: GameSets.actions,
      reads: const {Player, Fighter, BladeTrail},
      after: const [fighterDriver],
      runIf: hasResource<Scene>(),
    );
}

void announceWindup(World world) {
  final row = world
      .query2<Fighter, PlayerMotion>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (_, fighter, motion) = row;
  if (fighter.phase.state == CombatPhase.startup) {
    world.emit(PlayerWindup(motion.facing));
  }
}

void spawnPlayerFx(World world) {
  final row = world
      .query3<Fighter, PlayerMotion, SceneTransform>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (_, fighter, motion, transform) = row;

  if (fighter.phase.justEntered(CombatPhase.rolling)) {
    spawnDashDust(
      world,
      transform.translation.clone(),
      motion.rollDirection.clone(),
    );
  }
}

void updateBladeTrail(World world) {
  final row = world
      .query2<Fighter, BladeTrail>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (_, fighter, blade) = row;

  final swinging =
      fighter.phase.state == CombatPhase.active ||
      fighter.phase.state == CombatPhase.recovery;
  blade.trail
    ..emitting = swinging
    ..colorOverTrail = fighter.heavy ? heavyTrailFade : lightTrailFade;
}
