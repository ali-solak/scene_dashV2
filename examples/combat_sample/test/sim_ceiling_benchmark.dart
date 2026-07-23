/// Session 0a — the simulation ceiling, headless.
///
/// Spawns exactly N barbarians into the full combat cascade (every
/// fixed-step and update system; scene-gated visuals skip themselves) and
/// measures whole-frame cost at one fixed step per frame. The second
/// series adds four lava pits: `tickLavaPits` is the one O(pits × N)
/// system, and its per-enemy `Mired`/`Burning` re-adds also exercise the
/// `RemoveAfterTracker` row scan — the only quadratic candidates in the
/// sim.
///
/// Not part of the default suite (no `_test` suffix); run explicitly:
///
///     flutter test test/sim_ceiling_benchmark.dart
///
/// Debug-JIT numbers (asserts on), so absolute ms are pessimistic; the
/// SHAPE of the curve is the signal. Beside the human table, every series
/// emits one `sim-ceiling-result:` JSON line (plus one `sim-ceiling-env:`
/// with mode/OS), so before/after runs diff with a grep. Recorded runs
/// live in `benchmarks/results/`.
library;

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:combat_sample/enemies/enemies.dart';
import 'package:combat_sample/game/game_state.dart';
import 'package:combat_sample/player/player.dart' show Player;
import 'package:combat_sample/skills/skills.dart' show LavaPit;
import 'package:combat_sample/waves/waves.dart' show WaveState;
import 'package:flutter/foundation.dart'
    show debugPrint, kProfileMode, kReleaseMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import 'support/fight_harness.dart';

/// Past `risingSeconds` and into approach/circle, and enough frames that
/// the JIT has seen every hot path before the stopwatch starts.
const int warmupSteps = 180;
const int measuredSteps = 300;

/// Golden angle: an even, deterministic spread with no RNG.
const double _golden = 2.399963229728653;

/// Boots the full cascade, fields exactly [n] barbarians (the wave
/// director is parked engaged so it neither counts the fight cleared nor
/// fields more), optionally opens [pits] lava pits among them, and
/// returns measured milliseconds per frame.
double measureFrameMs(int n, {int pits = 0}) {
  final game = boot();
  final world = game.world;

  // Exact-N field: clear whatever wave 1 spawned.
  world.entitiesWith(require: const [Enemy]).each(world.despawn);
  game.pumpFixed(steps: 1);

  // The player must survive N barbarians pounding on it for the whole
  // measurement; a death would flip the state and gate the sim off.
  final player = playerOf(world);
  world.get<Health>(player)
    ..max = 1e12
    ..current = 1e12;

  for (var i = 0; i < n; i++) {
    final radius = 2.5 + 10.5 * i / math.max(1, n - 1);
    final theta = i * _golden;
    world.spawn(
      enemyBundle(
        math.sin(theta) * radius,
        math.cos(theta) * radius,
        index: i,
        health: 1e12, // burns and swings never thin the pack mid-measure
      ),
    );
  }
  for (var i = 0; i < pits; i++) {
    // On the circling ring, so the pack stays in the heat.
    final theta = i * math.pi / 2;
    world.spawn([
      LavaPit(1),
      SceneTransform(
        math.sin(theta) * circleRadius,
        0,
        math.cos(theta) * circleRadius,
      ),
      DespawnAfter(1e9),
    ]);
  }
  // Park the wave director: engaged with living > 0 early-outs forever,
  // so no intermission countdown and no extra barbarians mid-measure.
  world.resource<WaveState>()
    ..engaged = true
    ..intermission = 0;
  game.pumpFixed(steps: 1); // flush the queued spawns

  // (The first cook mass-adds `Burning` across the pack in one flush;
  // the S6 observer guard counts per entity since Session 1, so volume
  // alone no longer trips it and no seeding workaround is needed.)

  game.pumpFixed(steps: warmupSteps);
  final stopwatch = Stopwatch()..start();
  game.pumpFixed(steps: measuredSteps);
  stopwatch.stop();

  // Sanity: the fight is still on and the pack is still exactly N.
  expect(world.state<GameStatus>(), GameStatus.fighting);
  expect(world.query<Brawler>(require: const [Enemy]).count(), n);
  expect(world.entitiesWith(require: const [Player]).firstOrNull, isNotNull);

  return stopwatch.elapsedMicroseconds / measuredSteps / 1000;
}

void main() {
  test('simulation ceiling: ms per frame against barbarian count', () {
    // Printed per row, so a failing series still leaves the earlier rows.
    // The `sim-ceiling-*:` lines are the machine-readable record.
    final mode = kReleaseMode
        ? 'release'
        : kProfileMode
        ? 'profile'
        : 'debug';
    debugPrint(
      'sim-ceiling-env: {"os": "${Platform.operatingSystem}", '
      '"mode": "$mode", "measuredFrames": $measuredSteps}',
    );
    debugPrint(
      'sim ceiling — full cascade, headless, 1 fixed step per frame, '
      '$mode, $measuredSteps measured frames',
    );
    for (final n in const [10, 100, 300, 1000]) {
      final ms = measureFrameMs(n);
      final perBarb = ms * 1000 / n;
      debugPrint(
        '  N=${n.toString().padLeft(4)}: '
        '${ms.toStringAsFixed(3).padLeft(7)} ms/frame  '
        '(${perBarb.toStringAsFixed(2).padLeft(6)} µs/barb)',
      );
      debugPrint(
        'sim-ceiling-result: {"n": $n, "pits": 0, '
        '"msPerFrame": ${ms.toStringAsFixed(4)}}',
      );
    }
    final plain = measureFrameMs(300);
    final lava = measureFrameMs(300, pits: 4);
    debugPrint(
      '  N= 300 + 4 lava pits: ${lava.toStringAsFixed(3)} ms/frame '
      '(pit-free rerun ${plain.toStringAsFixed(3)}; the delta is '
      'tickLavaPits + RemoveAfterTracker re-adds)',
    );
    debugPrint(
      'sim-ceiling-result: {"n": 300, "pits": 0, '
      '"msPerFrame": ${plain.toStringAsFixed(4)}, "rerun": true}',
    );
    debugPrint(
      'sim-ceiling-result: {"n": 300, "pits": 4, '
      '"msPerFrame": ${lava.toStringAsFixed(4)}}',
    );
    debugPrint(
      '  60 Hz budget: 16.667 ms/frame; the fixed step alone must '
      'stay well under it.',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
