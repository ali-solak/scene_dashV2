/// Cross-feature input vocabulary. Held state lives in
/// `ButtonInput<CombatAction>`, buffered presses in
/// `InputBuffer<CombatAction>` (both `player/combat`); analog movement,
/// camera look, and the lock intents are declared here.
library;

/// Analog movement, camera-relative: +y is away from the camera.
enum MoveAxis { x, y }

/// The lock button (middle mouse / Tab): acquires when free, releases when
/// locked.
final class LockPressed {
  const LockPressed();
}

/// Cycles the lock to the next candidate by angle (Q) while locked.
final class LockCycled {
  const LockCycled();
}

/// Accumulated pointer-look input (mouse hover/drag on desktop, swipe on
/// touch): the widget adds pixel deltas, the camera system takes and
/// clears them once per frame.
final class LookInput {
  double _yawDeltaPixels = 0;
  double _pitchDeltaPixels = 0;

  void addDelta(double dxPixels, double dyPixels) {
    _yawDeltaPixels += dxPixels;
    _pitchDeltaPixels += dyPixels;
  }

  double takeYawDelta() {
    final delta = _yawDeltaPixels;
    _yawDeltaPixels = 0;
    return delta;
  }

  double takePitchDelta() {
    final delta = _pitchDeltaPixels;
    _pitchDeltaPixels = 0;
    return delta;
  }
}
