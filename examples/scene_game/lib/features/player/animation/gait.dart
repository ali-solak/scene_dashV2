/// Pure crab-leg pose and gait math — no scene or ECS dependencies, so the
/// leg geometry that has regressed before is unit-testable in isolation.
///
/// Stance convention: a leg reads as planted when the *world* elbow sum
/// `side.sign * (upperAngle + lowerAngle)` is negative (upper segment out and
/// up, lower segment folding back down). A positive sum reads as "legs
/// angled up" — the historical regression.
library;

import 'dart:math' as math;

import '../data/config.dart';

enum CrabLegSide {
  left(-1),
  right(1);

  const CrabLegSide(this.sign);

  final int sign;
}

/// Local-space target (collapsed or extended) for one crab leg.
final class CrabLegPose {
  const CrabLegPose({
    required this.rootX,
    required this.rootY,
    required this.rootZ,
    required this.rootYaw,
    required this.rootRoll,
    required this.upperAngle,
    required this.lowerAngle,
    required this.upperScale,
    required this.lowerScale,
  });

  final double rootX;
  final double rootY;
  final double rootZ;
  final double rootYaw;
  final double rootRoll;
  final double upperAngle;
  final double lowerAngle;
  final double upperScale;
  final double lowerScale;
}

final class CrabLegGaitSample {
  const CrabLegGaitSample({
    required this.extension,
    required this.gaitWeight,
    required this.lift,
    required this.stride,
    required this.bend,
  });

  final double extension;
  final double gaitWeight;
  final double lift;
  final double stride;
  final double bend;
}

double crabLegExtensionFor(double globalExtension, double delay) {
  final span = (1 - delay).clamp(0.001, 1.0);
  return ((globalExtension - delay) / span).clamp(0.0, 1.0).toDouble();
}

double crabLegSmoothStep(double value) {
  final t = value.clamp(0.0, 1.0).toDouble();
  return t * t * (3 - 2 * t);
}

double crabLegPhaseOffset(CrabLegSide side, int slot) {
  final groupA =
      (side == CrabLegSide.left && slot != 1) ||
      (side == CrabLegSide.right && slot == 1);
  final groupPhase = groupA ? 0.0 : math.pi;
  return groupPhase + slot * 0.23 + (side == CrabLegSide.left ? 0.07 : 0.0);
}

double advanceCrabGaitPhase(double phase, double movement01, double dt) {
  return phase + crabGaitSpeed * movement01.clamp(0.0, 1.0).toDouble() * dt;
}

CrabLegGaitSample sampleCrabLegGait({
  required double globalExtension,
  required double extensionDelay,
  required double movement01,
  required double direction,
  required double gaitPhase,
  required double phaseOffset,
}) {
  final extension = crabLegSmoothStep(
    crabLegExtensionFor(globalExtension, extensionDelay),
  );
  final gaitWeight = movement01.clamp(0.0, 1.0).toDouble() * extension;
  final phase = gaitPhase + phaseOffset;
  final wave = math.sin(phase);
  return CrabLegGaitSample(
    extension: extension,
    gaitWeight: gaitWeight,
    lift: math.max(0.0, wave) * crabLegLift * gaitWeight,
    stride: math.cos(phase) * crabLegStride * direction.sign * gaitWeight,
    bend: wave * crabLegBend * gaitWeight,
  );
}

/// The collapsed or extended pose target for one leg slot.
CrabLegPose crabLegPoseFor(
  CrabLegSide side,
  int slot, {
  required bool extended,
}) {
  final sign = side.sign.toDouble();
  final z = crabLegForwardOffsets[slot];
  final slotYaw = (slot - 1) * 0.34;
  if (!extended) {
    return CrabLegPose(
      rootX: sign * playerBodyVisualRadius * 0.32,
      rootY: -playerBodyVisualRadius * 0.08,
      rootZ: z * 0.56,
      rootYaw: slotYaw * 0.55,
      rootRoll: sign * 0.28,
      upperAngle: sign * 0.32,
      lowerAngle: sign * -0.95,
      upperScale: crabLegCollapsedScale,
      lowerScale: crabLegCollapsedScale,
    );
  }
  return CrabLegPose(
    rootX: sign * crabLegSideOffset,
    rootY: -playerBodyVisualRadius * 0.2,
    rootZ: z,
    rootYaw: slotYaw,
    rootRoll: sign * -0.06,
    upperAngle: sign * 0.46,
    lowerAngle: sign * -1.18,
    upperScale: 1,
    lowerScale: 1,
  );
}

CrabLegPose mixCrabLegPose(CrabLegPose a, CrabLegPose b, double t) {
  double lerp(double x, double y) => x + (y - x) * t;
  return CrabLegPose(
    rootX: lerp(a.rootX, b.rootX),
    rootY: lerp(a.rootY, b.rootY),
    rootZ: lerp(a.rootZ, b.rootZ),
    rootYaw: lerp(a.rootYaw, b.rootYaw),
    rootRoll: lerp(a.rootRoll, b.rootRoll),
    upperAngle: lerp(a.upperAngle, b.upperAngle),
    lowerAngle: lerp(a.lowerAngle, b.lowerAngle),
    upperScale: lerp(a.upperScale, b.upperScale),
    lowerScale: lerp(a.lowerScale, b.lowerScale),
  );
}
