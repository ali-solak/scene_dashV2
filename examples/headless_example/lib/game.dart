/// The smallest complete Scene-Dash v2 game, headless.
///
/// Everything the old annotated example needed a generator for is now
/// plain Dart: components are plain classes, tags implement [Tag], bundles
/// are functions returning lists, systems are stateless functions over the
/// world, and the `every(0.5)` cadence lives at the registration — no
/// timer resource, no plugin class, no codegen.
library;

import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';

// ── Components: plain data, no annotations, no registration ──────────────

final class Position {
  double x, y;
  Position(this.x, this.y);
}

final class Velocity {
  final double x, y;
  const Velocity(this.x, this.y);
}

/// A tag: presence-only, bit-cheap storage. Tags are the one component
/// kind that needs an install-time `registerTag<T>()` (a tag store cannot
/// be created from a spawned instance).
final class PlayerMarker implements Tag {}

/// Tags the short-lived pickup; its lifetime is the spawn list's
/// `DespawnAfter` — no cleanup system anywhere.
final class BoostMarker implements Tag {}

// ── Events & resources ────────────────────────────────────────────────────

final class PlayerSpawned {
  final Entity entity;
  const PlayerSpawned(this.entity);
}

/// The referee's tally — plain world data the test reads back.
final class RaceState {
  static const double finishLine = 1.0;

  int spawnsSeen = 0;
  int statusReports = 0;
  bool boostAvailable = false;
  Entity? winner;
}

// ── Bundles: functions returning lists ────────────────────────────────────

List<Object> playerBundle({double vx = 1, double vy = 2}) => [
      Position(0, 0),
      Velocity(vx, vy),
      PlayerMarker(),
    ];

List<Object> boostBundle() => [BoostMarker(), DespawnAfter(0.4)];

// ── Systems: stateless functions over the world ───────────────────────────

/// Startup: spawn the run and announce the player.
void spawnRun(World world) {
  final player = world.spawn(playerBundle());
  world.spawn(boostBundle());
  world.emit(PlayerSpawned(player));
}

/// Integrate velocity each fixed step — `world.dt` is the fixed delta
/// here, because the system is registered in a fixed schedule.
void move(World world) {
  world.query2<Position, Velocity>().each((_, position, velocity) {
    position
      ..x += velocity.x * world.dt
      ..y += velocity.y * world.dt;
  });
}

/// The referee: counts spawn events, tracks the boost and calls the race.
void referee(World world) {
  final race = world.resource<RaceState>();
  for (final _ in world.events<PlayerSpawned>()) {
    race.spawnsSeen++;
  }
  race.boostAvailable = world.entitiesWith(require: [BoostMarker]).count() > 0;
  if (race.winner == null) {
    final leader =
        world.query<Position>(require: [PlayerMarker]).firstOrNull;
    if (leader != null && leader.$2.x >= RaceState.finishLine) {
      race.winner = leader.$1;
    }
  }
}

/// Runs on the `every(0.5)` cadence declared at registration.
void reportStatus(World world) {
  world.resource<RaceState>().statusReports++;
}

// ── The feature install ───────────────────────────────────────────────────

/// The whole game as one feature: registrations mirror what the old
/// plugin's `build` did, minus the class and the codegen.
void installRace(GameBuilder game) {
  game.world.insert(RaceState());
  game
    ..registerTag<PlayerMarker>()
    ..registerTag<BoostMarker>()
    ..addSystem(Schedules.startup, spawnRun, writes: {Position, Velocity})
    ..addSystem(Schedules.fixedUpdate, move,
        writes: {Position}, reads: {Velocity})
    ..addSystem(Schedules.fixedUpdate, referee,
        reads: {Position}, after: [move])
    ..addSystem(Schedules.fixedUpdate, reportStatus,
        reads: const {}, runIf: every(0.5));
}
