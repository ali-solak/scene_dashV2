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
SpriteMaterial softAdditiveSprite() =>
    SpriteMaterial(colorTexture: softDotTexture())
      ..blendMode = SpriteBlendMode.additive;

// --- Fire wisp -----------------------------------------------------------

// Deterministic 2D value noise for the bake: hash lattice points, smooth
// interpolation, two octaves. Bake-time only, so clarity over speed.
double _hash(int x, int y) {
  var h = x * 374761393 + y * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  return ((h ^ (h >> 16)) & 0xffff) / 0xffff;
}

double _valueNoise(double x, double y) {
  final xi = x.floor(), yi = y.floor();
  final fx = x - xi, fy = y - yi;
  double smooth(double t) => t * t * (3 - 2 * t);
  final sx = smooth(fx), sy = smooth(fy);
  final a = _hash(xi, yi), b = _hash(xi + 1, yi);
  final c = _hash(xi, yi + 1), d = _hash(xi + 1, yi + 1);
  return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy;
}

/// A wisp puff: a radial body whose rim is eroded by angular noise (wispy,
/// irregular silhouette instead of a perfect disc) with a baked three-stop
/// ramp — [coreColor] at the hot center, [bodyColor] over the body,
/// [rimColor] at the edge. Straight (non-premultiplied) alpha: the sprite
/// shader treats sampled textures as straight and premultiplies on output,
/// so a premultiplied bake would darken every soft edge into a black rim.
/// Per-instance colors multiply on top, so over a particle's life the
/// whole ramp shifts together.
Uint8List _wispPixels(
  int size, {
  required (double, double, double) coreColor,
  required (double, double, double) bodyColor,
  required (double, double, double) rimColor,
}) {
  final pixels = Uint8List(size * size * 4);
  final center = (size - 1) / 2.0;
  final maxR = size / 2.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = (x - center) / maxR;
      final dy = (y - center) / maxR;
      final r = math.sqrt(dx * dx + dy * dy);
      final angle = math.atan2(dy, dx);
      // Two octaves of angular noise erode the rim; radial drift in the
      // sample keeps the erosion from being a static ring.
      final n =
          0.65 * _valueNoise(math.cos(angle) * 2.4 + 7, math.sin(angle) * 2.4) +
          0.35 * _valueNoise(math.cos(angle) * 5.1, math.sin(angle) * 5.1 + r);
      final edge = 0.62 + 0.36 * n;
      final t = (1.0 - r / edge).clamp(0.0, 1.0);
      final soft = t * t * (3 - 2 * t);
      final heat = math.pow(soft, 1.6).toDouble();
      final a = soft;
      // Ramp: rim -> body over the outer half, body -> core in the middle.
      final (br, bg, bb) = bodyColor;
      final (rr, rg, rb) = rimColor;
      final (cr, cg, cb) = coreColor;
      final mid = (soft * 1.7).clamp(0.0, 1.0);
      var red = rr + (br - rr) * mid + (cr - br) * heat;
      var green = rg + (bg - rg) * mid + (cg - bg) * heat;
      var blue = rb + (bb - rb) * mid + (cb - bb) * heat;
      final o = (y * size + x) * 4;
      pixels[o] = (red.clamp(0.0, 1.0) * 255).round();
      pixels[o + 1] = (green.clamp(0.0, 1.0) * 255).round();
      pixels[o + 2] = (blue.clamp(0.0, 1.0) * 255).round();
      pixels[o + 3] = (a * 255).round();
    }
  }
  return pixels;
}

Texture2D? _fireWisp;

/// The shared flame-puff sprite — white-hot core, orange body, deep red
/// rim. Built lazily on first use (scene-gated callers only, same as
/// [softDotTexture]).
Texture2D fireWispTexture() => _fireWisp ??= Texture2D.fromPixels(
  _wispPixels(
    128,
    coreColor: (1.0, 0.97, 0.82),
    bodyColor: (1.0, 0.55, 0.14),
    rimColor: (0.85, 0.18, 0.03),
  ),
  128,
  128,
);

/// The flame-puff sprite material. Source-over, not additive: this game's
/// sky is bright, and additive fire on a bright background can only push
/// toward white — it desaturates into pale cream. Alpha compositing lets
/// the flame occlude the sky and keep its deep orange.
SpriteMaterial fireSprite() =>
    SpriteMaterial(colorTexture: fireWispTexture())
      ..blendMode = SpriteBlendMode.alpha;
