part of '../player.dart';

// --- Locomotion (task 9) ---

// Scaled with the 2.6 u fighter: a bigger body covering the same ground
// per second reads as wading.
const double freeMoveSpeed = 6.2;

/// Strafe-set movement while locked is deliberately slower…
const double lockedMoveSpeed = 4.4;

/// …and backing off slower still (the back-off walk).
const double backpedalFactor = 0.75;

/// The dodge really moves you out of an arc now.
const double rollSpeed = 9.5;

/// Radians per second the fighter turns toward its velocity (free stance).
const double turnRate = 12;

const double playerSpawnX = 0;
const double playerSpawnZ = 5;

// --- Lock-on (task 10) ---

const double lockAcquireRange = 12;

/// Slightly wider than acquire so the lock does not flicker at the rim.
const double lockBreakRange = 15;

// Acquisition has no cone tunable anymore: nearest in front of the
// camera wins, behind-camera only as a fallback (see lockOnSystem).

// --- Camera (the CameraRig's souls framing: a pitch-orbit around the
// --- fighter's chest, smoothed, farther out than arm's length) ---

const double cameraDistance = 9.0;
const double cameraFocusHeight = 2.0;

/// Pitch clamp: slightly below level up to nearly top-down.
const double cameraPitchMin = -0.1;
const double cameraPitchMax = 1.15;

/// The elevation the locked camera eases to.
const double cameraLockedPitch = 0.32;

/// Exponential smoothing rates (higher = snappier): yaw only steers
/// itself while locked; the position always chases its orbit point.
const double cameraYawSharpness = 5;
const double cameraPositionSharpness = 14;
const double cameraPitchSharpness = 6;

/// Radians of free-camera orbit per pixel of pointer travel. Pushing the
/// mouse up looks up (the camera dives); flip the pitch sign to invert.
const double lookYawSensitivity = 0.006;
const double lookPitchSensitivity = 0.0045;

/// How fast a heavy hit's camera kick settles.
const double cameraKickDecay = 7;

/// How long the flinch reads for after a blow that did not stagger.
/// Short: a long wince would look like a stagger the fighter can act out of.
const double flinchSeconds = 0.28;

/// Camera kick when the player is hit. Smaller than a heavy connect's:
/// the screen must not lurch harder for taking a blow than landing one.
const double hurtCameraKick = 0.4;

/// How far the locked camera's focus slides from the player toward the
/// midpoint of the two fighters (0 = player only, 1 = pure midpoint).
const double lockedCameraBias = 0.5;

/// Metres the locked camera pulls back per metre between the fighters,
/// and the ceiling on that. Without it the target walks out of frame.
const double lockedDistanceGain = 0.55;
const double maxLockedCameraDistance = 16;

// --- Title framing (the shot behind the start menu) ---

/// Far enough out to read as "here is the place you will fight in", high
/// enough to show the clearing rather than the knight's back.
const double titleCameraDistance = 26;
const double titleCameraPitch = 0.42;

/// Radians per second the title shot drifts around the clearing. Slow:
/// a held shot breathing, not a turntable.
const double titleOrbitRate = 0.08;

/// The opening push-in: travel time from the title framing onto the
/// fighter, and the slower blend it flies on. Without the slow blend the
/// normal sharpness snaps the camera in over a few frames, a cut not an
/// arrival.
const double introZoomSeconds = 1.6;
const double introCameraSharpness = 2.2;

// --- Graybox body (fallback when character assets are absent) ---

const double playerCapsuleRadius = 0.42;
const double playerCapsuleHeight = 0.95;

const double playerMaxHealth = 100;

// --- Animation mapper (task 15; timings stay phase-driven, L2) ---

/// Pinned at a hard sub-frame cut: cross-clip blends can fold joints (the
/// long-path slerp "pancake"), and it reappeared on device whenever these
/// were raised, even with the hemisphere alignment pass in place (see
/// NOTES.md B1). Cut transitions ship; folding characters do not.
const double locomotionFadeSeconds = 0.001;
const double oneShotFadeSeconds = 0.001;

/// The tail snaps too: it was the last cross-clip blend left and the fold
/// showed up exactly where it ran. Snapping costs nothing now that the
/// attack windows in `combat.dart` are sized so clips finish on their own.
const double oneShotFadeOutSeconds = 0.001;

/// Ground speed each loop clip was authored for: playback scales with
/// actual speed so feet stop sliding. Scaled with the character height.
const double walkStrideSpeed = 2.4;
const double runStrideSpeed = 6.0;
const double strafeStrideSpeed = 4.3;
const double backpedalStrideSpeed = 2.2;

/// Free-stance speed above which the run clip takes over from the walk.
const double runBlendSpeed = 4.8;

/// Clip lengths (from the rig files, docs/asset_inventory.md); the mapper
/// scales playback so the clip spans the machine's phase windows, never
/// the reverse (L2). Two-handed set, to match the 2H axe.
const double strikeClipSeconds = 1.10; // Melee_2H_Attack_Slice
const double heavyClipSeconds = 2.40; // Melee_2H_Attack_Spin
const double rollClipSeconds = 0.40;
const double hitClipSeconds = 0.67;
const double windCastClipSeconds = 1.167; // Jump_Full_Short (the cast leap)

/// Peak height of the wind-gust hop before the gust lands.
const double windCastHopHeight = 0.8;

/// The hop is a real ballistic arc under [knockbackGravity]. While it
/// lasts the movement system owns `transform.y` (the knockback step would
/// read a rising y as a launch and fight it). Kept off Knockback on
/// purpose so a hop never flags the fighter airborne; you keep control.
final double windCastJumpSpeed = math.sqrt(
  2 * knockbackGravity * windCastHopHeight,
);

/// Seconds the hop spends off the ground (up and back). The jump clip and
/// the leap both run for exactly this, so animation and arc land together.
final double windCastSeconds = 2 * windCastJumpSpeed / knockbackGravity;

/// Dodge clips play at this speed instead of being stretched across the
/// full window; the directional dodge clip is the dash. One because the
/// 0.40 s clip already fits the 0.45 s roll window, so speeding it up
/// only looked fast-forwarded.
const double rollPlaybackScale = 1.0;

/// Ceiling on one-shot playback: a clip is never sped past this to fit a
/// short gameplay window. The attack windows in `combat.dart` are sized
/// so clip/window lands at ~1.55: a swing plays a touch quick and reaches
/// its last frame just as the machine returns to idle.
const double maxOneShotPlaybackScale = 1.55;

/// Radians per second a thrown body turns over onto its back. Slow
/// enough to see it happen across the arc, fast enough to be flat by the
/// time it lands.
const double proneSettleRate = 2.6;

/// The blade ribbon's colour. A heavy leaves a hotter streak than a
/// light; alpha is the ribbon's overall strength, tapered along its
/// length by the vertex colours.
final Vector4 lightTrailTint = Vector4(0.80, 0.90, 1.0, 0.75);
final Vector4 heavyTrailTint = Vector4(1.0, 0.62, 0.22, 0.9);

/// You keep some purchase while winding up and recovering; attacks are
/// committing, not a full stop. Zero during the active frames and while
/// staggered.
const double attackMoveFactor = 0.35;
