part of '../creeps.dart';

final class const Creep() implements Tag;

final class PathProgress {
  int next = 1;
}

final class Velocity(final double maxSpeed) {
  final Vector3 value = Vector3.zero();
}

final class Raider {
  final GameTimer bite = GameTimer(raiderBiteSeconds);
}
