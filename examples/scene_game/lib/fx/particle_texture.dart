// Soft round particle sprites. Untextured billboards render as hard-edged
// squares; a radial-falloff dot turns each particle into a soft glowing orb
// (nicer than the old opaque instanced spheres, and additive-friendly).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';

/// A soft radial dot: bright premultiplied core fading smoothly to a
/// transparent edge. Premultiplied (rgb already scaled by the falloff) so it
/// reads correctly under both additive and alpha compositing. Slightly
/// hot-cored so additive stacks bloom pleasantly.
Uint8List _softDotPixels(int size) {
  final pixels = Uint8List(size * size * 4);
  final center = (size - 1) / 2.0;
  final maxR = size / 2.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = (x - center) / maxR;
      final dy = (y - center) / maxR;
      final r = math.sqrt(dx * dx + dy * dy).clamp(0.0, 1.0);
      // Smooth radial falloff with a brighter core.
      final t = (1.0 - r).clamp(0.0, 1.0);
      final soft = t * t * (3 - 2 * t); // smoothstep
      final core = math.pow(t, 3).toDouble(); // hot center
      final a = (soft * 0.75 + core * 0.25).clamp(0.0, 1.0);
      final v = (a * 255).round();
      final o = (y * size + x) * 4;
      pixels[o] = v; // premultiplied white
      pixels[o + 1] = v;
      pixels[o + 2] = v;
      pixels[o + 3] = v;
    }
  }
  return pixels;
}

Texture2D? _softDot;

/// The shared soft-dot particle sprite, built lazily on first use (needs the
/// GPU context, so call only once resources are ready — every emitter is
/// already scene-gated).
Texture2D softDotTexture() =>
    _softDot ??= Texture2D.fromPixels(_softDotPixels(64), 64, 64);

/// A soft additive sprite material carrying the dot.
SpriteMaterial softAdditiveSprite() => SpriteMaterial(
  colorTexture: softDotTexture(),
)..blendMode = SpriteBlendMode.additive;
