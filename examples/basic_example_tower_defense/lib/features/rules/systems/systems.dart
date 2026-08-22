part of '../rules.dart';

void loseLife(World world) {
  final lives = world.resource<Lives>();
  for (final _ in world.events<CreepReachedEnd>()) {
    if (--lives.value > 0) continue;
    lives.value = 0;
    world.setState(GameStatus.lost);
  }
}

void collectBounty(World world) {
  final gold = world.resource<Gold>();
  for (final kill in world.events<CreepKilled>()) {
    gold.value += kill.bounty;
  }
}

void startRun(World world) {
  world.resource<Lives>().value = startingLives;
  world.resource<Gold>().value = startingGold;
}
