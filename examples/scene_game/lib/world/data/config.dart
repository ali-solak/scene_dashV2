/// World, ramp dimension and camera tuning for the scene game example.
library;

// --- Ramp (a wide, finite inclined platform) ---

/// Ramp size along X (width), Y (thickness) and Z (length), in world units.
const double rampWidth = 16;
const double rampThickness = 1;
const double rampLength = 36;

/// Ramp incline in radians (rotation about X). The +Z end tips downhill, so
/// rocks spawned at the -Z (high) end roll toward +Z.
const double rampInclineRadians = 0.18;

// --- World ---

const double gravityStrength = 18;

// --- Camera ---

const double cameraFollowSharpness = 8;
