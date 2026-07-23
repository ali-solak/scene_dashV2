part of '../player.dart';

const double freeMoveSpeed = 6.2;

const double lockedMoveSpeed = 4.4;

const double backpedalFactor = 0.75;

const double rollSpeed = 9.5;

const double turnRate = 12;

const double playerSpawnX = 0;
const double playerSpawnZ = 5;

const double lockAcquireRange = 12;

const double lockBreakRange = 15;

const double cameraDistance = 9.0;
const double cameraFocusHeight = 2.0;

const double cameraPitchMin = -0.1;
const double cameraPitchMax = 1.15;

const double cameraLockedPitch = 0.32;

const double cameraYawSharpness = 5;
const double cameraPositionSharpness = 14;
const double cameraPitchSharpness = 6;

const double lookYawSensitivity = 0.006;
const double lookPitchSensitivity = 0.0045;

const double cameraKickDecay = 7;

const double flinchSeconds = 0.28;

const double hurtCameraKick = 0.4;

const double lockedCameraBias = 0.5;

const double lockedDistanceGain = 0.55;
const double maxLockedCameraDistance = 16;

const double titleCameraDistance = 26;
const double titleCameraPitch = 0.42;

const double titleOrbitRate = 0.08;

const double introZoomSeconds = 1.6;
const double introCameraSharpness = 2.2;

const double playerCapsuleRadius = 0.42;
const double playerCapsuleHeight = 0.95;

const double playerMaxHealth = 100;

const double locomotionFadeSeconds = 0.001;
const double oneShotFadeSeconds = 0.001;

const double oneShotFadeOutSeconds = 0.001;

const double walkStrideSpeed = 2.4;
const double runStrideSpeed = 6.0;
const double strafeStrideSpeed = 4.3;
const double backpedalStrideSpeed = 2.2;

const double runBlendSpeed = 4.8;

const double strikeClipSeconds = 1.10;
const double heavyClipSeconds = 2.40;
const double rollClipSeconds = 0.40;
const double hitClipSeconds = 0.67;
const double windCastClipSeconds = 1.167;

const double windCastHopHeight = 0.8;

final double windCastJumpSpeed = math.sqrt(
  2 * knockbackGravity * windCastHopHeight,
);

final double windCastSeconds = 2 * windCastJumpSpeed / knockbackGravity;

const double rollPlaybackScale = 1.0;

const double maxOneShotPlaybackScale = 1.55;

const double proneSettleRate = 2.6;

final Vector4 lightTrailTint = Vector4(0.80, 0.90, 1.0, 0.75);
final Vector4 heavyTrailTint = Vector4(1.0, 0.62, 0.22, 0.9);

const double attackMoveFactor = 0.35;
