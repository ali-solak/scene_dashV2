// Isolates the *synchronization arithmetic* the flutter_scene integration runs
// every frame: composing a SceneTransform's translation/rotation/scale into a
// node's local Matrix4 and marking it dirty. It deliberately iterates a flat
// list (no sparse query) so the numbers reflect the matrix/dirty work only —
// the query-iteration cost is measured separately (representative_benchmark).
//
// The question this answers: is changed-only sync (a per-transform dirty flag
// that skips matrix composition for unchanged entities) worth adopting over the
// current unconditional sync? Compare the rows below across changed ratios.
//
// Run: dart run benchmarks/transform_sync_benchmark.dart [entityCount]
import 'package:scene_dash_v2_benchmarks/harness.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

/// Stand-in for the bridge's `SceneTransform` (the real type lives in the
/// flutter_scene package, which we don't depend on here).
final class Trs {
  final Vector3 translation;
  final Quaternion rotation;
  final Vector3 scale;
  bool dirty;
  Trs(this.translation, this.rotation, this.scale, {this.dirty = true});
}

/// Stand-in for a flutter_scene `Node`: a local matrix plus a dirty bit.
final class FakeNode {
  final Matrix4 localTransform = Matrix4.identity();
  bool transformDirty = false;
  void markTransformDirty() => transformDirty = true;
}

(List<Trs>, List<FakeNode>) _build(int n, double changedRatio) {
  final transforms = <Trs>[];
  final nodes = <FakeNode>[];
  final changeEvery = changedRatio <= 0 ? n + 1 : (1 / changedRatio).round();
  for (var i = 0; i < n; i++) {
    transforms.add(
      Trs(
        Vector3(i.toDouble(), 0, 0),
        Quaternion.axisAngle(Vector3(0, 1, 0), i * 0.001),
        Vector3.all(1),
        dirty: changedRatio >= 1 || (i % changeEvery == 0),
      ),
    );
    nodes.add(FakeNode());
  }
  return (transforms, nodes);
}

void main(List<String> args) {
  final base = entityCount(args);
  for (final n in {100, 1000, 10000, 50000, base}.toList()..sort()) {
    section('Transform synchronization', entities: n);

    // Current behavior: compose full TRS for every entity, unconditionally.
    final (full, fullNodes) = _build(n, 1);
    benchRepeat('full TRS sync (unconditional)', n, () {
      for (var i = 0; i < n; i++) {
        final t = full[i];
        fullNodes[i]
          ..localTransform.setFromTranslationRotationScale(
            t.translation,
            t.rotation,
            t.scale,
          )
          ..markTransformDirty();
      }
    });

    // Translation-only write (setTranslationRaw) — the cheap path for entities
    // that only move, no rotation/scale composition.
    final (transOnly, transNodes) = _build(n, 1);
    benchRepeat('translation-only sync', n, () {
      for (var i = 0; i < n; i++) {
        final t = transOnly[i];
        transNodes[i]
          ..localTransform.setTranslationRaw(
            t.translation.x,
            t.translation.y,
            t.translation.z,
          )
          ..markTransformDirty();
      }
    });

    // Changed-only sync: check a dirty flag per entity, compose only the
    // changed (dirty) subset. Swept across realistic changed ratios. The 0% row
    // is the floor (pure dirty-check cost over all N). Flags are left set so a
    // fixed working set is composed on every timed run; clearing one bool per
    // changed entity is negligible and excluded.
    for (final ratio in [0.0, 0.1, 0.5, 1.0]) {
      final (transforms, syncNodes) = _build(n, ratio);
      final pct = (ratio * 100).toStringAsFixed(0);
      benchRepeat('changed-only sync ($pct% changed)', n, () {
        for (var i = 0; i < n; i++) {
          final t = transforms[i];
          if (!t.dirty) continue;
          syncNodes[i]
            ..localTransform.setFromTranslationRotationScale(
              t.translation,
              t.rotation,
              t.scale,
            )
            ..markTransformDirty();
        }
      });
    }
  }
}
