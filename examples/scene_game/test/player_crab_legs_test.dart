import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:scene_game/player/data/config.dart';
import 'package:scene_game/player/animation/gait.dart';

void main() {
  test('player leg definitions include three legs per side', () {
    expect(crabLegsPerSide, 3);
    expect(crabLegCount, 6);
    expect(crabLegForwardOffsets, <double>[
      crabLegFrontOffset,
      crabLegMiddleOffset,
      crabLegRearOffset,
    ]);
  });

  test('extension clamps and staggers front, middle and rear legs', () {
    expect(crabLegExtensionFor(-1, 0), 0);
    expect(crabLegExtensionFor(2, 0), 1);

    final front = crabLegExtensionFor(0.3, 0);
    final middle = crabLegExtensionFor(0.3, crabLegExtensionStagger);
    final rear = crabLegExtensionFor(0.3, crabLegExtensionStagger * 2);

    expect(front, greaterThan(middle));
    expect(middle, greaterThan(rear));
  });

  test('gait groups are approximately half a cycle apart', () {
    final leftFront = crabLegPhaseOffset(CrabLegSide.left, 0);
    final rightFront = crabLegPhaseOffset(CrabLegSide.right, 0);

    expect((rightFront - leftFront).abs(), closeTo(math.pi, 0.1));
  });

  test('zero movement keeps gait influence at rest', () {
    final sample = sampleCrabLegGait(
      globalExtension: 1,
      extensionDelay: 0,
      movement01: 0,
      direction: 1,
      gaitPhase: 0,
      phaseOffset: 0,
    );

    expect(sample.gaitWeight, 0);
    expect(sample.lift, 0);
    expect(sample.stride, 0);
    expect(sample.bend, 0);
  });

  test('movement advances phase and direction mirrors stride only', () {
    expect(advanceCrabGaitPhase(2, 0, 0.25), 2);
    expect(advanceCrabGaitPhase(2, 1, 0.25), greaterThan(2));

    final right = sampleCrabLegGait(
      globalExtension: 1,
      extensionDelay: 0,
      movement01: 1,
      direction: 1,
      gaitPhase: 0,
      phaseOffset: 0,
    );
    final left = sampleCrabLegGait(
      globalExtension: 1,
      extensionDelay: 0,
      movement01: 1,
      direction: -1,
      gaitPhase: 0,
      phaseOffset: 0,
    );

    expect(left.stride, closeTo(-right.stride, 1e-9));
    expect(left.lift, right.lift);
  });

  test('folded legs suppress gait influence', () {
    final folded = sampleCrabLegGait(
      globalExtension: 0,
      extensionDelay: 0,
      movement01: 1,
      direction: 1,
      gaitPhase: 0,
      phaseOffset: 0,
    );

    expect(folded.gaitWeight, 0);
  });

  test('visual leg span does not change central body hit radius', () {
    final visualSpan =
        crabLegSideOffset + crabLegUpperLength + crabLegLowerLength;

    expect(visualSpan, greaterThan(playerBodyVisualRadius));
    expect(playerCollisionRadius, playerBodyVisualRadius);
    expect(playerCollisionRadius, lessThan(visualSpan));
  });

  test('leg poses keep the planted stance (world elbow sum negative)', () {
    // Regression guard: legs read as "angled up" when the world-space sum of
    // upper and lower angles goes positive for a side.
    for (final side in CrabLegSide.values) {
      for (var slot = 0; slot < crabLegsPerSide; slot++) {
        for (final extended in [false, true]) {
          final pose = crabLegPoseFor(side, slot, extended: extended);
          final worldElbowSum =
              side.sign * (pose.upperAngle + pose.lowerAngle);
          expect(
            worldElbowSum,
            lessThan(0),
            reason:
                '$side slot $slot (extended: $extended) must fold downward',
          );
        }
      }
    }
  });

  test('pose mixing hits both endpoints exactly', () {
    final collapsed = crabLegPoseFor(CrabLegSide.right, 0, extended: false);
    final extended = crabLegPoseFor(CrabLegSide.right, 0, extended: true);

    final atStart = mixCrabLegPose(collapsed, extended, 0);
    final atEnd = mixCrabLegPose(collapsed, extended, 1);

    expect(atStart.upperAngle, collapsed.upperAngle);
    expect(atStart.upperScale, collapsed.upperScale);
    expect(atEnd.upperAngle, extended.upperAngle);
    expect(atEnd.upperScale, extended.upperScale);
  });
}
