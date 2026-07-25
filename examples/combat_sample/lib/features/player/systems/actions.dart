part of '../player.dart';

/// The combat machine and everything hanging off its edges: the windup
/// broadcast the pack dodges on, the roll dust, and the blade trail.
///
/// [fighterDriver] registers here because every other system in this
/// group orders after it, and `lockOnSystem` exempts this group's
/// systems by reference, so all of it must be registered before lock-on.
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

/// Kicks up earth on the frame a dodge commits (a no-op headless).
/// Broadcasts the windup so the pack can read it without depending on
/// the player feature (see [PlayerWindup]). Emitted every step of the
/// windup rather than on its entry edge, so a barbarian evaluating its
/// dodge mid-windup still sees it.
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

/// Off the machine's entry edge, not the input: a buffered roll can fire
/// a frame or two after the press. (The swing's crescent lives in the
/// rules feature, built from the hit check's reach and arc.)
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
      // dirt is thrown away from the committed dodge direction.
      motion.rollDirection.clone(),
    );
  }
}

/// Feeds the blade ribbon (a no-op headless).
///
/// Samples while the swing is live and RETRACTS the rest of the time, so
/// the trail draws itself on during the cut and pulls back in after,
/// instead of popping in and out.
void updateBladeTrail(World world) {
  final row = world
      .query2<Fighter, BladeTrail>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (_, fighter, blade) = row;

  final swinging = switch (fighter.phase.state) {
    CombatPhase.active || CombatPhase.recovery => true,
    _ => false,
  };
  if (swinging) {
    blade.trail.sample(blade.weapon.globalTransform);
  } else {
    blade.trail.retract();
  }
  blade.trail.rebuild(fighter.heavy ? heavyTrailTint : lightTrailTint);
}
