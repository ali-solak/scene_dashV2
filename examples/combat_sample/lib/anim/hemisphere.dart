/// Aligns quaternion keyframe signs for stable blending.
library;

// ignore_for_file: implementation_imports
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_scene/scene.dart' show Animation;
import 'package:flutter_scene/src/animation.dart'
    show AnimationProperty, RotationTimelineResolver;
import 'package:vector_math/vector_math.dart' show Quaternion;

/// Enables rotation diagnostics.
const bool debugHemispheres = false;

/// Aligns every rotation channel across [animations] to a shared
/// hemisphere, per joint. Call once per set of clips that will ever be
/// blended together (they have to agree with each other), after loading
/// and before any clip is instantiated.
void harmoniseRotationHemispheres(Iterable<Animation> animations) {
  var seenChannels = 0;
  var seenKeys = 0;
  var flipped = 0;
  var skipped = 0;
  // nodeName -> the orientation every clip's keyframes for that joint are
  // measured against. The first clip to mention a joint sets it, which is
  // arbitrary but consistent; all that matters is that everyone agrees.
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

      // `values` hands back an unmodifiable list, but the quaternions in
      // it are the live objects; mutating them in place is how this
      // reaches the keyframes at all.
      final keys = resolver.values;
      if (keys.isEmpty) continue;

      final node = channel.bindTarget.nodeName;
      // Use the first clip as the joint anchor.
      final anchor = reference.putIfAbsent(node, () => keys.first.clone());

      // Align each key to the previous rotation.
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
