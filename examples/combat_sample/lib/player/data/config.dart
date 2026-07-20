part of '../player.dart';

// --- Locomotion (task 9) ---

// Scaled with the 2.6 u fighter — a bigger body covering the same ground
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

/// How far the locked camera's focus slides from the player toward the
/// midpoint of the two fighters (0 = player only, 1 = pure midpoint).
const double lockedCameraBias = 0.5;

/// Metres the locked camera pulls back per metre between the fighters,
/// and the ceiling on that. Without this the camera holds a fixed leash
/// and the target simply walks out of frame — the lock stops framing the
/// fight and just points at it.
const double lockedDistanceGain = 0.55;
const double maxLockedCameraDistance = 16;

// --- Graybox body (fallback when character assets are absent) ---

const double playerCapsuleRadius = 0.42;
const double playerCapsuleHeight = 0.95;

const double playerMaxHealth = 100;

// --- Animation mapper (task 15; timings stay phase-driven — L2) ---

/// Real crossfades — restored.
///
/// These were pinned at 0.001 (a hard, sub-frame cut) to dodge the
/// pancake: upstream's slerp takes the LONG path between antipodal
/// quaternions, so any cross-clip blend could fold joints the wrong way
/// round. Snapping meant no clip ever held a mid-blend, and the artefact
/// had nowhere to happen — at the cost of every transition in the game
/// being a visible cut.
///
/// `harmoniseRotationHemispheres` (anim/hemisphere.dart) now removes the
/// cause instead of avoiding it: no two clips hold opposite-signed
/// quaternions for the same joint any more, so slerp is never handed a
/// pair it would take the long way between.
///
/// AND IT CAME BACK. Restored to the hard snap.
///
/// The alignment pass is still in place and still correct as far as its
/// own tests go, but the pancake reappeared on device the moment these
/// were raised — on the barbarians' attack (a skinned mesh collapsing
/// along an axis, reported as "becoming slimmer") and on their corpses.
/// So the sign mismatch is either not the cause, or not the only one.
///
/// Flip `debugHemispheres` in anim/hemisphere.dart to find out which: if
/// it reports 0 flips, the exporter was already consistent and the whole
/// theory is wrong. Until that question is answered these stay at the
/// value that is known to work, because a game with cut transitions
/// ships and a game with folding characters does not.
const double locomotionFadeSeconds = 0.001;
const double oneShotFadeSeconds = 0.001;

/// No exception any more: the tail snaps too.
///
/// This was 0.12 on the theory that a clip being blended AWAY from could
/// not pancake, because there is no long-path target to travel to. That
/// was wrong, and the way it was caught is worth keeping: with every
/// other fade pinned at 0.001, this tail was the ONLY cross-clip blend
/// left in the game — and the fold appeared exactly where it ran, in the
/// beat after a dodge finished. One blend, one artefact, same place.
///
/// Two things follow. The artefact really is a blending problem, not
/// something else wearing its coat. And `harmoniseRotationHemispheres`
/// does NOT prevent it, so sign mismatch is not the cause, or not the
/// whole cause — see NOTES.md B1.
///
/// Snapping costs nothing here now. The tail existed because clips were
/// being cut off mid-follow-through, and that was fixed properly instead:
/// the attack windows in `combat.dart` are sized so the clip REACHES its
/// last frame just as the machine returns to idle, and the roll's 0.40 s
/// clip already fits inside its 0.45 s window. There is nothing left to
/// ride out.
const double oneShotFadeOutSeconds = 0.001;

/// Ground speed each loop clip was authored for: playback scales with
/// actual speed so feet stop sliding ("clips a bit" = stride mismatch).
/// Scaled with the character — a 1.44× taller fighter covers 1.44× the
/// ground per stride cycle.
const double walkStrideSpeed = 2.4;
const double runStrideSpeed = 6.0;
const double strafeStrideSpeed = 4.3;
const double backpedalStrideSpeed = 2.2;

/// Free-stance speed above which the run clip takes over from the walk.
const double runBlendSpeed = 4.8;

/// Clip lengths (read from the rig files, docs/asset_inventory.md); the
/// mapper scales playback so the clip spans the machine's phase windows —
/// never the reverse (L2). Two-handed set, to match the 2H sword.
const double strikeClipSeconds = 1.10; // Melee_2H_Attack_Slice
const double heavyClipSeconds = 1.63; // Melee_2H_Attack_Chop
const double rollClipSeconds = 0.40;
const double hitClipSeconds = 0.67;

/// Dodge clips play at this speed instead of being stretched across the
/// full window. The directional dodge clip IS the dash — no procedural
/// tumble/lean.
///
/// One, for the same reason as [maxOneShotPlaybackScale]: the 0.40 s clip
/// already fits inside the 0.45 s roll window, so speeding it up bought
/// nothing except the fast-forwarded look.
const double rollPlaybackScale = 1.0;

/// Ceiling on one-shot playback: a clip is never sped past this to fit
/// its (short) gameplay window.
///
/// Slightly brisk, never fast-forwarded. The attack windows in
/// `combat.dart` are sized so that clip/window lands AT this number:
/// 1.10/0.71 and 1.63/1.05 both come out at ~1.55. That is the whole
/// point — the swing plays a touch quick and reaches its last frame just
/// as the machine returns to idle, so it neither sprints nor stops
/// halfway.
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

/// You keep some purchase while winding up and recovering — attacks are
/// committing, not a full stop. Zero during the active frames (that IS
/// the commitment) and while staggered.
const double attackMoveFactor = 0.35;
