import 'package:flutter_scene/scene.dart' show AnimationClip;

final class ClipHold {
  final Map<AnimationClip, double> _scales = {};

  bool get holding => _scales.isNotEmpty;

  bool hold(bool held, Iterable<AnimationClip> clips) {
    if (held == holding) return holding;
    if (held) {
      for (final clip in clips) {
        _scales[clip] = clip.playbackTimeScale;
        clip.playbackTimeScale = 0;
      }
    } else {
      _scales.forEach((clip, scale) => clip.playbackTimeScale = scale);
      _scales.clear();
    }
    return holding;
  }
}
