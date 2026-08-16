library;

const double rampWidth = 16;
const double rampThickness = 1;
const double rampLength = 36;

const double rampInclineRadians = 0.18;

const double gravityStrength = 18;

// Seconds to close half the remaining gap. Replaces a naive `dt * 8` lerp,
// which drifted with the frame rate and snapped outright below 8fps; matched
// to the old feel at 60fps.
const double cameraFollowHalfLife = 0.08;
