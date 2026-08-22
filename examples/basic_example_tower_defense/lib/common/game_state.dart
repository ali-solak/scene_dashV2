library;

import 'dart:ui' show Offset, Size;

enum GameStatus { playing, lost }

/// Raw placement intent from the Flutter shell. The tower system resolves the
/// screen point through the active scene camera and owns the whole operation.
final class const PlaceTowerRequested(
  final Offset position,
  final Size viewSize,
);

final class const CreepReachedEnd();

final class const CreepKilled(final int bounty);
