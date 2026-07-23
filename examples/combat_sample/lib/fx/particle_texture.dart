/// Soft round particle sprites. Untextured billboards render as
/// hard-edged squares; a radial-falloff dot turns each particle into a
/// soft glowing spark.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';

/// A soft radial dot: bright premultiplied core fading to a transparent
/// edge. Premultiplied (rgb already scaled by the falloff) so it reads
/// correctly under additive compositing.
Uint8List _softDotPixels(int size) {
  final pixels = Uint8List(size * size * 4);
  final center = (size - 1) / 2.0;
  final maxR = size / 2.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = (x - center) / maxR;
      final dy = (y - center) / maxR;
      final r = math.sqrt(dx * dx + dy * dy).clamp(0.0, 1.0);
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

/// The shared soft-dot sprite, built lazily on first use (needs the GPU
/// context, so every call site is already scene-gated).
Texture2D softDotTexture() =>
    _softDot ??= Texture2D.fromPixels(_softDotPixels(64), 64, 64);

/// A flame tongue: a teardrop tapering to a point, so a spray reads as
/// licking spikes rather than round blobs. Wide and bright at the base
/// (v = 0), pinched and dim at the tip. Soft round dots turn a gush of
/// fire into white mist.
Uint8List _flamePixels(int size) {
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    // 0 at the base, 1 at the tip.
    final t = y / (size - 1);
    // The silhouette: fattest just above the base, pinching to nothing.
    final halfWidth = math.sin((1 - t) * math.pi * 0.72) * 0.5;
    for (var x = 0; x < size; x++) {
      final dx = (x / (size - 1) - 0.5).abs();
      // Soft across the tongue, so edges do not alias into hard wedges.
      final across = halfWidth <= 0
          ? 0.0
          : (1.0 - (dx / halfWidth)).clamp(0.0, 1.0);
      final soft = across * across * (3 - 2 * across);
      // Hottest at the base and burning out along the length.
      final along = (1.0 - t) * (1.0 - t);
      final a = (soft * along).clamp(0.0, 1.0);
      final v = (a * 255).round();
      final o = (y * size + x) * 4;
      pixels[o] = v; // premultiplied white; the particle colour tints it
      pixels[o + 1] = v;
      pixels[o + 2] = v;
      pixels[o + 3] = v;
    }
  }
  return pixels;
}

Texture2D? _flame;

/// The shared flame-tongue sprite.
Texture2D flameTexture() =>
    _flame ??= Texture2D.fromPixels(_flamePixels(64), 64, 64);

SpriteMaterial? _flameSprite;

/// A soft additive sprite material carrying the flame tongue.
SpriteMaterial flameAdditiveSprite() =>
    _flameSprite ??= SpriteMaterial(colorTexture: flameTexture())
      ..blendMode = SpriteBlendMode.additive;

/// A crisp blob: opaque through most of its radius with a thin
/// antialiasing rim, shaded brighter top-left so it reads as a ball.
/// Unlike the soft dot it has an edge, so clusters do not bloom together.
Uint8List _crispDotPixels(int size) {
  final pixels = Uint8List(size * size * 4);
  final center = (size - 1) / 2.0;
  final maxR = size / 2.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = (x - center) / maxR;
      final dy = (y - center) / maxR;
      final r = math.sqrt(dx * dx + dy * dy);
      // Solid to 0.82, then a short ramp to nothing: an edge, not a haze.
      final t = ((1.0 - r) / 0.18).clamp(0.0, 1.0);
      final a = t * t * (3 - 2 * t);
      // Cheap sphere shading: brighter where a light above-left would sit.
      final lit = (0.62 + 0.38 * (1.0 - (dx + 0.35).abs() - (dy + 0.35).abs()))
          .clamp(0.35, 1.0);
      final v = (a * lit * 255).round();
      final o = (y * size + x) * 4;
      pixels[o] = v; // premultiplied: rgb already scaled by alpha
      pixels[o + 1] = v;
      pixels[o + 2] = v;
      pixels[o + 3] = (a * 255).round();
    }
  }
  return pixels;
}

Texture2D? _crispDot;

/// The shared crisp-blob sprite.
Texture2D crispDotTexture() =>
    _crispDot ??= Texture2D.fromPixels(_crispDotPixels(64), 64, 64);

SpriteMaterial? _crispSprite;

/// The crisp blob under ALPHA blending: molten globs that occlude each
/// other and the ground, with defined edges. Additive would let every
/// overlap add up into the bloom that swallows their shape.
SpriteMaterial crispAlphaSprite() =>
    _crispSprite ??= SpriteMaterial(colorTexture: crispDotTexture())
      ..blendMode = SpriteBlendMode.alpha;

/// A puff: a rounded body with a soft but definite edge and internal
/// shading, so a cluster reads as tumbling volumes of burning gas.
/// Sits between the soft dot (all falloff, cloudy) and the crisp glob
/// (too solid for flame): the glob's shading with a wider rim.
Uint8List _puffPixels(int size) {
  final pixels = Uint8List(size * size * 4);
  final center = (size - 1) / 2.0;
  final maxR = size / 2.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = (x - center) / maxR;
      final dy = (y - center) / maxR;
      final r = math.sqrt(dx * dx + dy * dy);
      // Solid core out to ~0.55, then a wide soft shoulder.
      final t = ((1.0 - r) / 0.45).clamp(0.0, 1.0);
      final a = t * t * (3 - 2 * t);
      // The same cheap shading the globs use: a puff has a lit side and a
      // shadowed one, which is most of what makes it read as a volume.
      final lit = (0.55 + 0.45 * (1.0 - (dx + 0.3).abs() - (dy + 0.3).abs()))
          .clamp(0.3, 1.0);
      final o = (y * size + x) * 4;
      pixels[o] = (a * lit * 255).round(); // premultiplied
      pixels[o + 1] = (a * lit * 255).round();
      pixels[o + 2] = (a * lit * 255).round();
      pixels[o + 3] = (a * 255).round();
    }
  }
  return pixels;
}

Texture2D? _puff;

/// The shared puff sprite.
Texture2D puffTexture() =>
    _puff ??= Texture2D.fromPixels(_puffPixels(64), 64, 64);

SpriteMaterial? _puffSprite;

/// Puffs under alpha blending. Additive fire sums toward white where
/// puffs overlap; alpha puffs occlude each other, so the mass keeps its
/// edges and depth.
SpriteMaterial puffAlphaSprite() =>
    _puffSprite ??= SpriteMaterial(colorTexture: puffTexture())
      ..blendMode = SpriteBlendMode.alpha;

SpriteMaterial? _alphaSprite;

/// The soft dot under alpha blending, for dust and thrown earth:
/// additive dirt would glow, which is the one thing dirt does not do.
SpriteMaterial softAlphaSprite() =>
    _alphaSprite ??= SpriteMaterial(colorTexture: softDotTexture())
      ..blendMode = SpriteBlendMode.alpha;

SpriteMaterial? _sprite;

/// The shared soft additive sprite material. One instance for every
/// emitter: building a fresh material per hit caused GPU setup stutter
/// mid-swing. Nothing mutates it after construction, so sharing is safe.
SpriteMaterial softAdditiveSprite() =>
    _sprite ??= SpriteMaterial(colorTexture: softDotTexture())
      ..blendMode = SpriteBlendMode.additive;
