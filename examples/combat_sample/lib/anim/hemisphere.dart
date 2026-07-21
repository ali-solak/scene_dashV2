/// Canonicalises the SIGN of every rotation keyframe, so cross-clip
/// blending takes the short way round.
///
/// ## The bug this exists for
///
/// A quaternion and its negation describe the same orientation, so an
/// exporter is free to emit either. flutter_scene 0.19's `slerp`
/// (`math_extensions.dart`) does not negate for antipodal inputs, so when
/// two clips happen to hold opposite-signed quaternions for the same
/// joint, blending between them travels the LONG way — all the way around
/// the hypersphere instead of across the short arc. On a character rig
/// that reads as the model folding flat for a few frames: the "pancake"
/// that cost this sample its animation blending entirely (NOTES.md B1).
///
/// The upstream fix is one line in `slerp`. Until it lands, we can get
/// the same result from the other side: if no two clips ever hold
/// antipodal quaternions for the same joint, `slerp` is never handed a
/// pair it would take the long way between.
///
/// ## What this does
///
/// Picks a reference orientation per joint and flips every keyframe that
/// points into the opposite hemisphere (`dot < 0`), in place. The pose is
/// completely unchanged — `q` and `-q` are the same rotation — only the
/// representation is. Within a clip, each keyframe is aligned to the one
/// before it, so intra-clip slerp is short-path too.
///
/// Uses implementation imports for the same reason `fx/particles.dart`
/// does: the keyframe types are not exported from the barrel. The
/// exception is confined to this file.
library;

// ignore_for_file: implementation_imports
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_scene/scene.dart' show Animation;
import 'package:flutter_scene/src/animation.dart'
    show AnimationProperty, RotationTimelineResolver;
import 'package:vector_math/vector_math.dart' show Quaternion;

/// Aligns every rotation channel across [animations] to a shared
/// hemisphere, per joint.
///
/// Call ONCE per set of clips that will ever be blended together (they
/// have to agree with each other, so a per-clip pass would be useless),
/// after loading and before any clip is instantiated.
/// Flip to true to have the pass report what it saw. If `channels` is 0
/// the clips are not carrying `RotationTimelineResolver`s and this whole
/// file is a no-op; if `flipped` is 0 the exporter was already
/// consistent and the pancake is NOT a sign problem.
const bool debugHemispheres = false;

void harmoniseRotationHemispheres(Iterable<Animation> animations) {
  var seenChannels = 0;
  var seenKeys = 0;
  var flipped = 0;
  var skipped = 0;
  // nodeName -> the orientation every clip's keyframes for that joint are
  // measured against. The first clip to mention a joint sets it, which is
  // arbitrary but consistent — all that matters is that everyone agrees.
  final reference = <String, Quaternion>{};

  for (final animation in animations) {
    for (final channel in animation.channels) {
      if (channel.bindTarget.property != AnimationProperty.rotation) continue;
      final resolver = channel.resolver;
      if (resolver is! RotationTimelineResolver) {
        skipped++;
        continue;
      }
      seenChannels++;

      // `values` hands back an unmodifiable LIST, but the quaternions in
      // it are the live objects — mutating them in place is how this
      // reaches the keyframes at all.
      final keys = resolver.values;
      if (keys.isEmpty) continue;

      final node = channel.bindTarget.nodeName;
      // The shared anchor is set by the FIRST clip to mention this joint
      // and never moves again.
      //
      // It used to be overwritten with each clip's first keyframe, which
      // is exactly the drift it was meant to prevent: clip B aligned to
      // A, then became the anchor for C, so C could end up antipodal to
      // A even though every individual step looked aligned. That is what
      // left the barbarians pancaking on their attack clip while the
      // player looked fine.
      final anchor = reference.putIfAbsent(node, () => keys.first.clone());

      // Align this clip's first keyframe to the shared anchor, then chain
      // the rest to their predecessor so a joint winding more than 180°
      // across the clip does not flip back and forth against a fixed
      // reference.
      var previous = anchor;
      for (final key in keys) {
        seenKeys++;
        if (_dot(key, previous) < 0) {
          _negate(key);
          flipped++;
        }
        previous = key;
      }
    }
  }
  if (debugHemispheres) {
    _report(seenChannels, seenKeys, flipped, skipped, reference.length);
  }
}

void _report(int channels, int keys, int flipped, int skipped, int joints) {
  debugPrint(
    'hemisphere: $channels rotation channels over $joints joints, '
    '$keys keyframes, $flipped flipped, $skipped non-timeline channels '
    'skipped',
  );
}

double _dot(Quaternion a, Quaternion b) =>
    a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;

void _negate(Quaternion q) => q.setValues(-q.x, -q.y, -q.z, -q.w);
