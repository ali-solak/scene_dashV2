part of '../creeps.dart';

final class const Creep() implements Tag;

final class PathProgress {
  int next = 1;
}

final class const Speed(final double value);

final class Raider {
  final GameTimer bite = GameTimer(raiderBiteSeconds);
}
