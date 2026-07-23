/// A small complete headless game.
library;

import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';

// Components

final class Position {
  double x, y;
  Position(this.x, this.y);
}

final class Velocity {
  final double x, y;
  const Velocity(this.x, this.y);
}

final class PlayerMarker implements Tag {}

final class BoostMarker implements Tag {}

// Events and resources

final class PlayerSpawned {
  final Entity entity;
  const PlayerSpawned(this.entity);
}

final class RaceState {
  static const double finishLine = 1.0;

  int spawnsSeen = 0;
  int statusReports = 0;
  bool boostAvailable = false;
  Entity? winner;
}

// Bundles

List<Object> playerBundle({double vx = 1, double vy = 2}) => [
  Position(0, 0),
  Velocity(vx, vy),
  PlayerMarker(),
];

List<Object> boostBundle() => [BoostMarker(), DespawnAfter(0.4)];

// Systems

void spawnRun(World world) {
  final player = world.spawn(playerBundle());
  world.spawn(boostBundle());
  world.emit(PlayerSpawned(player));
}

void move(World world) {
  world.query2<Position, Velocity>().each((_, position, velocity) {
    position
      ..x += velocity.x * world.dt
      ..y += velocity.y * world.dt;
  });
}

void referee(World world) {
  final race = world.resource<RaceState>();
  for (final _ in world.events<PlayerSpawned>()) {
    race.spawnsSeen++;
  }
  race.boostAvailable = world.entitiesWith(require: [BoostMarker]).count() > 0;
  if (race.winner == null) {
    final leader = world.query<Position>(require: [PlayerMarker]).firstOrNull;
    if (leader != null && leader.$2.x >= RaceState.finishLine) {
      race.winner = leader.$1;
    }
  }
}

void reportStatus(World world) {
  world.resource<RaceState>().statusReports++;
}

/// Installs the game's data and systems.
void installRace(GameBuilder game) {
  game.world.insert(RaceState());
  game
    ..registerTag<PlayerMarker>()
    ..registerTag<BoostMarker>()
    ..addSystem(Schedules.startup, spawnRun, writes: {Position, Velocity})
    ..addSystem(
      Schedules.fixedUpdate,
      move,
      writes: {Position},
      reads: {Velocity},
    )
    ..addSystem(
      Schedules.fixedUpdate,
      referee,
      reads: {Position},
      after: [move],
    )
    ..addSystem(
      Schedules.fixedUpdate,
      reportStatus,
      reads: const {},
      runIf: every(0.5),
    );
}
