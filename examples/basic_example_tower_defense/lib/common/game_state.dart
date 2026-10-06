library;

import 'dart:ui' show Offset, Size;

enum GameStatus { playing, lost }

/// Raw placement intent from the Flutter shell. The tower system resolves the
/// screen point through the active scene camera and owns the whole operation.
final class const PlaceTowerRequested(
  final Offset position,
  final Size viewSize,
);

final class BoardPointer {
  Offset? position;
  Size viewSize = Size.zero;
}

final class const CreepReachedEnd();

final class const WaveCleared(final int wave, final int bonus);
