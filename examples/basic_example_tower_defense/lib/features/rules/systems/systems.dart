part of '../rules.dart';

void loseLife(World world) {
  final lives = world.resource<Lives>();
  world.eachEvent<CreepReachedEnd>((_) {
    if (--lives.value > 0) return;
    lives.value = 0;
    world.setState(GameStatus.lost);
  });
}

void collectBounty(World world) {
  final gold = world.resource<Gold>();
  world.eachEvent<Destroyed>((destroyed) {
    gold.value += destroyed.bounty;
  });
}

void startRun(World world) {
  world.resource<Lives>().value = startingLives;
  world.resource<Gold>().value = startingGold;
}

void collectWaveBonus(World world) {
  final gold = world.resource<Gold>();
  world.eachEvent<WaveCleared>((cleared) {
    gold.value += cleared.bonus;
  });
}
