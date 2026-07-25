/// Soft round particle sprites. Untextured billboards render as
/// hard-edged squares; a radial-falloff dot turns each particle into a
/// soft glowing spark.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/noise.dart';
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

/// A droplet: the soft dot without its hot core, and dimmer. Sea spray
/// is many faint specks that read as haze together, so the core spike
/// that makes a spark pop is exactly what makes a droplet look like a
/// hard bright dot. The falloff is gentle the whole way in, so nothing
/// in the sprite resolves to a point.
Uint8List _dropletPixels(int size) {
  final pixels = Uint8List(size * size * 4);
  final center = (size - 1) / 2.0;
  final maxR = size / 2.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = (x - center) / maxR;
      final dy = (y - center) / maxR;
      final r = math.sqrt(dx * dx + dy * dy).clamp(0.0, 1.0);
      final a = math.pow(1.0 - r, 1.7).toDouble() * 0.65;
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

Texture2D? _droplet;

/// The shared droplet sprite.
Texture2D dropletTexture() =>
    _droplet ??= Texture2D.fromPixels(_dropletPixels(64), 64, 64);

SpriteMaterial? _dropletSprite;

/// Droplets under additive blending: faint alone, catching the light
/// where a burst of them overlaps.
SpriteMaterial dropletAdditiveSprite() =>
    _dropletSprite ??= SpriteMaterial(colorTexture: dropletTexture())
      ..blendMode = SpriteBlendMode.additive;

/// Approximate blackbody colour for a normalized temperature, from
/// extinguished black up through deep red and orange to yellow. Stops
/// short of white on purpose: the flame sprites composite additively, so
/// a white-hot core would leave the stack nowhere left to climb.
(double, double, double) _blackbody(double temp) {
  const stops = <(double, double, double, double)>[
    (0.00, 0.00, 0.00, 0.00),
    (0.22, 0.35, 0.02, 0.00),
    (0.48, 0.85, 0.16, 0.01),
    (0.72, 1.00, 0.48, 0.06),
    (1.00, 1.00, 0.82, 0.35),
  ];
  final t = temp.clamp(0.0, 1.0);
  for (var i = 1; i < stops.length; i++) {
    if (t <= stops[i].$1) {
      final a = stops[i - 1];
      final b = stops[i];
      final f = (t - a.$1) / (b.$1 - a.$1);
      return (
        a.$2 + (b.$2 - a.$2) * f,
        a.$3 + (b.$3 - a.$3) * f,
        a.$4 + (b.$4 - a.$4) * f,
      );
    }
  }
  return (1.0, 0.82, 0.35);
}

/// A flame tongue: a teardrop tapering to a point, so a spray reads as
/// licking spikes rather than round blobs. Wide and hot at the base
/// (v = 0), pinched and cooling at the tip. Soft round dots turn a gush
/// of fire into white mist.
///
/// Two noise fields do the work a smooth gradient cannot. A domain warp
/// bends the silhouette so tongues lick and split instead of staying
/// airbrushed teardrops, and a second field breaks the interior into hot
/// and cool filaments, mapped through [_blackbody] so a single puff
/// carries its own temperature structure.
Uint8List _flamePixels(int size) {
  final pixels = Uint8List(size * size * 4);
  final warp = FastNoiseLite()
    ..seed = 7
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 3;
  final detail = FastNoiseLite()
    ..seed = 8
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 3;
  for (var y = 0; y < size; y++) {
    // 0 at the base, 1 at the tip.
    final t = y / (size - 1);
    // The silhouette: fattest just above the base, pinching to nothing.
    final halfWidth = math.sin((1 - t) * math.pi * 0.72) * 0.5;
    for (var x = 0; x < size; x++) {
      final u = x / (size - 1) - 0.5;
      // The warp grows toward the tip, where flame is free to wander.
      final warped = u + warp.getNoise2(u * 4.4, t * 2.4) * 0.16 * t;
      final across = halfWidth <= 0
          ? 0.0
          : (1.0 - (warped.abs() / halfWidth)).clamp(0.0, 1.0);
      final soft = across * across * (3 - 2 * across);
      final n = detail.getNoise2(warped * 5.6, t * 3.4) * 0.5 + 0.5;
      // Hottest at the base and burning out along the length.
      final along = (1.0 - t) * (1.0 - t);
      // Frays toward the tip instead of ending in a clean point.
      final density = soft * along * (0.55 + 0.55 * n);
      final a = ((density - 0.06 * t) / 0.9).clamp(0.0, 1.0);
      // The filaments read as temperature, not just as brightness.
      final temp = (a * (1.15 - 0.35 * t) * (0.72 + 0.5 * n)).clamp(0.0, 1.0);
      final (r, g, b) = _blackbody(temp);
      final o = (y * size + x) * 4;
      // Premultiplied; the particle colour tints it further.
      pixels[o] = (r * a * 255).round();
      pixels[o + 1] = (g * a * 255).round();
      pixels[o + 2] = (b * a * 255).round();
      pixels[o + 3] = (a * 255).round();
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

Uint8List _puffPixels(int size) {
  final pixels = Uint8List(size * size * 4);
  final noise = FastNoiseLite()
    ..seed = 17
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 4;
  final center = (size - 1) / 2.0;
  final maxR = size / 2.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = (x - center) / maxR;
      final dy = (y - center) / maxR;
      final r = math.sqrt(dx * dx + dy * dy);
      // Solid core out to ~0.55, then a wide soft shoulder.
      final t = ((1.0 - r) / 0.45).clamp(0.0, 1.0);
      final round = t * t * (3 - 2 * t);
      final billow = 1.0 - noise.getNoise2(dx * 1.9, dy * 1.9).abs();
      final density = round * (0.42 + 0.58 * billow * billow);
      final a = ((density - 0.10) / 0.62).clamp(0.0, 1.0);
      // Lobes catch the light; the underside stays shadowed.
      final lit = ((0.58 + 0.42 * billow) * (0.92 - 0.22 * dy)).clamp(0.3, 1.0);
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
