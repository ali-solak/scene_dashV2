/// Pure clearing layout: where every tree, rock, and bush stands. Split from
/// the spawn system so the ring geometry is headless-testable.
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

  /// Uniform 0..1 roll; the spawner maps it onto its template list, so the
  /// layout stays independent of how many variants were loaded.
  final double variantRoll;
}

/// Whether [theta] falls in the cliff gap: the one sector (toward the
/// sun) the treeline leaves open, where the plateau drops to the sea.
bool inCliffSector(double theta) {
  var difference = (theta - cliffAzimuth) % (2 * math.pi);
  if (difference > math.pi) difference -= 2 * math.pi;
  if (difference < -math.pi) difference += 2 * math.pi;
  return difference.abs() < cliffHalfAngle;
}

/// Lays the clearing out deterministically from [clearingSeed]: a dense,
/// evenly-spaced jittered tree ring with an underbrush ring at its feet
/// (the level reads closed), rocks and bushes scattered between arena and
/// treeline — and nothing at all in the cliff sector, where the view runs
/// out over the water.
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
    // The codebase's azimuth convention throughout: atan2(x, z), i.e.
    // x = sin, z = cos — the same space [inCliffSector] tests.
    x: math.sin(theta) * r,
    z: math.cos(theta) * r,
    yaw: rng.nextDouble() * 2 * math.pi,
    scale: propScale * jitter,
    variantRoll: rng.nextDouble(),
  );
}
