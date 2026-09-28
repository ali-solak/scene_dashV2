part of '../feedback.dart';

void installDashFx(GameBuilder game) {
  game
    ..addSystem(
      Schedules.update,
      kickDashDust,
      inSet: GameSets.logic,
      reads: const {},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      ringShockwaveDust,
      inSet: GameSets.logic,
      reads: const {},
      runIf: hasResource<Scene>(),
    );
}

void ringShockwaveDust(World world) {
  final rig = world.resource<CameraRig>();
  for (final wave in world.events<Shockwave>()) {
    rig.shake.addTrauma(shockwaveTrauma);
    for (var i = 0; i < shockwaveDustPuffs; i++) {
      final angle = i * 2 * math.pi / shockwaveDustPuffs;
      spawnDashDust(
        world,
        wave.position,
        Vector3(math.sin(angle), 0, math.cos(angle)),
      );
    }
  }
}

void kickDashDust(World world) {
  for (final dash in world.events<Dashed>()) {
    spawnDashDust(world, dash.position, dash.heading);
  }
}
