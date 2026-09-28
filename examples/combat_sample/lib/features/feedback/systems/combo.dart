part of '../feedback.dart';

void installCombo(GameBuilder game) {
  game
    ..world.insert(ComboMeter())
    ..addSystem(
      Schedules.fixedUpdate,
      countCombo,
      inSet: GameSets.resolution,
      reads: const {Player, Enemy},
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      OnEnter(GameStatus.fighting),
      resetCombo,
      reads: const {},
      runIf: freshRun,
    );
}

void countCombo(World world) {
  final meter = world.resource<ComboMeter>();
  meter.sinceHit += world.dt;
  if (meter.sinceHit > comboTimeoutSeconds) meter.drop();
  for (final hit in world.events<DamageDealt>()) {
    if (!hit.impact) continue;
    if (world.has<Player>(hit.target)) {
      meter.drop();
    } else if (world.has<Enemy>(hit.target)) {
      meter.land();
    }
  }
}

void resetCombo(World world) => world.resource<ComboMeter>().reset();
