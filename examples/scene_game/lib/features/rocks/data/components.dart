part of '../rocks.dart';

final class Rock implements Tag {
  const Rock();
}

final class Flaming implements Tag {
  const Flaming();
}

final class RockVisuals {
  RockVisuals(this.shell);

  final Node shell;
}

final class RockHitReaction {
  const RockHitReaction({required this.strength});

  final double strength;
}
