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
      announceShockwave,
      inSet: GameSets.actions,
      reads: const {Player, Fighter, SceneTransform},
      after: const [fighterDriver],
    )
    ..addSystem(
      Schedules.fixedUpdate,
      announceDash,
      inSet: GameSets.movement,
      reads: const {Player, Fighter, PlayerMotion, SceneTransform},
      after: const [movePlayer],
    )
    ..addSystem(
      Schedules.fixedUpdate,
      updateDashTrail,
      inSet: GameSets.actions,
      reads: const {Player, Fighter, DashTrail},
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

void announceShockwave(World world) {
  world.query2<Fighter, SceneTransform>(require: const [Player]).each((
    _,
    fighter,
    transform,
  ) {
    if (!fighter.phase.justEntered(CombatPhase.active)) return;
    if (!fighter.swing.shockwave) return;
    world.emit(Shockwave(transform.translation.clone()..y = 0));
  });
}

void announceDash(World world) {
  world
      .query3<Fighter, PlayerMotion, SceneTransform>(require: const [Player])
      .each((entity, fighter, motion, transform) {
        if (!fighter.phase.justEntered(CombatPhase.rolling)) return;
        world.emit(
          Dashed(
            entity,
            transform.translation.clone(),
            motion.rollDirection.clone(),
          ),
        );
      });
}

void updateDashTrail(World world) {
  world.query2<Fighter, DashTrail>(require: const [Player]).each((
    _,
    fighter,
    dash,
  ) {
    dash.trail.emitting = fighter.phase.state == CombatPhase.rolling;
  });
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
