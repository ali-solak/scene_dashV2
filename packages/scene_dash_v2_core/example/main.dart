// A complete headless game: two racers, one system, no Flutter.
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';

final class Position {
  double x;
  Position(this.x);
}

final class Velocity {
  final double x;
  const Velocity(this.x);
}

final class Racer implements Tag {
  const Racer();
}

final class Winner {
  Entity? entity;
}

void installRace(GameBuilder game) {
  game
    ..registerTag<Racer>()
    ..world.insert(Winner())
    ..addSystem(Schedules.startup, spawnRacers, writes: {Position, Velocity})
    ..addSystem(Schedules.fixedUpdate, advance, writes: {Position})
    ..addSystem(Schedules.fixedUpdate, checkFinish, after: const [advance]);
}

void spawnRacers(World world) {
  world.spawn([const Racer(), Position(0), const Velocity(1.0)]);
  world.spawn([const Racer(), Position(0), const Velocity(1.4)]);
}

void advance(World world) {
  world.query2<Position, Velocity>(require: const [Racer]).each((
    entity,
    position,
    velocity,
  ) {
    position.x += velocity.x * world.dt;
  });
}

void checkFinish(World world) {
  final winner = world.resource<Winner>();
  if (winner.entity != null) return;
  world.query<Position>(require: const [Racer]).eachUntil((entity, position) {
    if (position.x < 10) return true; // keep scanning
    winner.entity = entity;
    return false; // stop
  });
}

void main() {
  final game = TestGame.headless(features: [installRace]);

  // Identical spawns and inputs give identical runs, so this is a test.
  game.pumpFixed(steps: 600); // 10s at 60Hz

  final winner = game.world.resource<Winner>().entity;
  print('winner: $winner');
  for (final (entity, position) in game.world.query<Position>().records) {
    print('  $entity at ${position.x.toStringAsFixed(2)}m');
  }
}
