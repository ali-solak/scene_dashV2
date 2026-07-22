// The stage's headless half: the feature set boots clean under strictAccess
// (declarations honest, scene-gated systems skipped without a Scene), the
// clearing layout respects its rings, and the arena clamp holds fighters in.
import 'dart:math' as math;

import 'package:combat_sample/world/data/arena.dart';
import 'package:combat_sample/world/data/assets.dart';
import 'package:combat_sample/world/data/config.dart';
import 'package:combat_sample/world/data/layout.dart';
import 'package:combat_sample/world/world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

void main() {
  test('the stage feature boots clean under strictAccess + throw', () {
    final game = TestGame.headless(
      strictAccess: true,
      features: [installWorld(WorldAssets.none())],
    );
    game.start();
    // Scene-gated startup systems were skipped; the wind resource exists.
    expect(game.world.hasResource<WorldAssets>(), isTrue);
    game.pump();
  });

  test('the clearing layout keeps its rings and leaves the cliff gap open', () {
    final placements = layoutClearing();
    // The sector skips thin the requested counts; the ring must still be
    // populated densely enough to read closed.
    expect(
      placements.where((p) => p.kind == PropKind.tree).length,
      greaterThan(treeCount ~/ 2),
    );
    expect(
      placements.where((p) => p.kind == PropKind.bush).length,
      greaterThan((bushCount + underbrushCount) ~/ 2),
    );
    for (final p in placements) {
      final r = math.sqrt(p.x * p.x + p.z * p.z);
      switch (p.kind) {
        case PropKind.tree:
          expect(r, inInclusiveRange(treeRingInner, treeRingOuter));
        case PropKind.rock:
          expect(r, inInclusiveRange(scatterInner, scatterOuter));
        case PropKind.bush:
          // Scatter bushes start at the arena edge; underbrush hugs the
          // treeline — the union of both bands.
          expect(
            r,
            inInclusiveRange(
              math.min(scatterInner, underbrushRadius - underbrushJitter),
              scatterOuter,
            ),
          );
      }
      // Nothing stands inside the fighting circle…
      expect(r, greaterThan(arenaRadius));
      // …or in the cliff sector, where the view runs out to the sea.
      expect(
        inCliffSector(math.atan2(p.x, p.z)),
        isFalse,
        reason: 'the gap toward the sun stays open',
      );
      expect(p.variantRoll, inInclusiveRange(0, 1));
    }
    // Deterministic: the same seed lays the same clearing.
    final again = layoutClearing();
    for (var i = 0; i < placements.length; i++) {
      expect(again[i].x, placements[i].x);
      expect(again[i].z, placements[i].z);
    }
  });

  test('clampToArena holds positions inside the bounds radius', () {
    final inside = Vector3(3, 0.5, -4);
    expect(clampToArena(inside), isFalse);
    expect(inside.storage, [3.0, 0.5, -4.0]);

    final outside = Vector3(arenaBoundsRadius + 5, 1.2, 0);
    expect(clampToArena(outside), isTrue);
    expect(outside.x, closeTo(arenaBoundsRadius, 1e-5));
    // Grounding is not the clamp's business (1e-5: 32-bit vector storage).
    expect(outside.y, closeTo(1.2, 1e-5));
    expect(outside.z, 0);

    // A diagonal escape lands on the rim, direction preserved.
    final diagonal = Vector3(20, 0, 20);
    clampToArena(diagonal);
    expect(
      math.sqrt(diagonal.x * diagonal.x + diagonal.z * diagonal.z),
      closeTo(arenaBoundsRadius, 1e-5),
    );
    expect(diagonal.x, closeTo(diagonal.z, 1e-5));
  });
}
