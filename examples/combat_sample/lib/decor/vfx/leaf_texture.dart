/// A generated leaf silhouette: a pointed blade with a midrib, as an
/// alpha mask.
///
/// Generated rather than shipped, like the grass blade mask and the lava
/// crust; it keeps the CC0 asset fence (L5) intact and costs one small
/// texture upload.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';

/// RGBA pixels for a [size]×[size] leaf. White where the leaf is, with a
/// darker midrib and a soft edge; the material tints it.
Uint8List leafPixels(int size) {
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    // 0 at the stem, 1 at the tip.
    final v = y / (size - 1);
    // A leaf is widest around a third of the way up and tapers to a
    // point: sin gives the belly, the exponent pulls the tip sharp.
    final halfWidth = math.pow(math.sin(v * math.pi), 0.72) * 0.46;
    for (var x = 0; x < size; x++) {
      final u = (x / (size - 1)) - 0.5;
      final distance = u.abs();
      final o = (y * size + x) * 4;
      if (halfWidth <= 0 || distance > halfWidth) {
        pixels[o + 3] = 0; // outside the blade
        continue;
      }
      // Soft edge over the outer fifth, so the silhouette is not jagged.
      final edge = (1 - distance / halfWidth) / 0.2;
      final alpha = edge.clamp(0.0, 1.0);
      final soft = alpha * alpha * (3 - 2 * alpha);

      // The midrib: a darker line up the centre, plus a little shading
      // toward the edges so the leaf is not a flat cutout.
      final rib = 1 - math.exp(-(distance * distance) / 0.0015) * 0.45;
      final shade = (0.72 + 0.28 * (1 - distance / halfWidth)) * rib;
      final value = (shade * 255).round().clamp(0, 255);

      pixels[o] = value;
      pixels[o + 1] = value;
      pixels[o + 2] = value;
      pixels[o + 3] = (soft * 255).round();
    }
  }
  return pixels;
}

Texture2D? _leaf;

/// The shared leaf mask, built lazily on first use (needs the GPU
/// context, so every call site is already scene-gated).
Texture2D leafTexture() =>
    _leaf ??= Texture2D.fromPixels(leafPixels(64), 64, 64);
