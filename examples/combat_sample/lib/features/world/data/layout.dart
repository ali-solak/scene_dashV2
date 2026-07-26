/// Clearing prop layout.
library;

import 'dart:math' as math;

import 'config.dart';

enum PropKind { tree, rock, bush }

class PropPlacement {
  const PropPlacement({
    required this.kind,
    required this.x,
    required this.z,
    required this.yaw,
    required this.scale,
    required this.variantRoll,
  });

  final PropKind kind;
  final double x;
  final double z;
  final double yaw;

  /// Final uniform scale (propScale × jitter).
  final double scale;

  /// Uniform variant value.
  final double variantRoll;
}

/// Whether [theta] is inside the cliff gap.
bool inCliffSector(double theta) {
  var difference = (theta - cliffAzimuth) % (2 * math.pi);
  if (difference > math.pi) difference -= 2 * math.pi;
  if (difference < -math.pi) difference += 2 * math.pi;
  return difference.abs() < cliffHalfAngle;
}

/// Builds a deterministic clearing layout.
List<PropPlacement> layoutClearing({int seed = clearingSeed}) {
  final rng = math.Random(seed);
  final placements = <PropPlacement>[];

  void place(PropKind kind, double theta, double r) {
    final placement = _placement(kind, rng, theta, r);
    if (inCliffSector(theta)) return; // after the rng draws: determinism
    placements.add(placement);
  }

  for (var i = 0; i < treeCount; i++) {
    // Even angular spacing with jitter keeps the ring closed.
    final theta =
        (i + (rng.nextDouble() - 0.5) * 0.7) * (2 * math.pi / treeCount);
    final r =
        treeRingInner + rng.nextDouble() * (treeRingOuter - treeRingInner);
    place(PropKind.tree, theta, r);
  }
  for (var i = 0; i < underbrushCount; i++) {
    final theta =
        (i + (rng.nextDouble() - 0.5) * 0.8) * (2 * math.pi / underbrushCount);
    final r =
        underbrushRadius + (rng.nextDouble() - 0.5) * 2 * underbrushJitter;
    place(PropKind.bush, theta, r);
  }
  for (var i = 0; i < rockCount; i++) {
    final theta = rng.nextDouble() * 2 * math.pi;
    final r = scatterInner + rng.nextDouble() * (scatterOuter - scatterInner);
    place(PropKind.rock, theta, r);
  }
  for (var i = 0; i < bushCount; i++) {
    final theta = rng.nextDouble() * 2 * math.pi;
    final r = scatterInner + rng.nextDouble() * (scatterOuter - scatterInner);
    place(PropKind.bush, theta, r);
  }
  return placements;
}

PropPlacement _placement(
  PropKind kind,
  math.Random rng,
  double theta,
  double r,
) {
  final jitter =
      propScaleJitterMin +
      rng.nextDouble() * (propScaleJitterMax - propScaleJitterMin);
  return PropPlacement(
    kind: kind,
    // Arena azimuth coordinates.
    x: math.sin(theta) * r,
    z: math.cos(theta) * r,
    yaw: rng.nextDouble() * 2 * math.pi,
    scale: propScale * jitter,
    variantRoll: rng.nextDouble(),
  );
}
