/// A procedurally generated lava crust: cooled black rock cracked open by
/// glowing molten channels.
///
/// This exists because the authored `lava.fmat` cannot be relied on. Two
/// authored materials in this sample have already failed to render with
/// no error anyone could act on (NOTES.md B4), and a lava pit is a DAMAGE
/// ZONE — a hazard you cannot see is worse than an ugly one. So the pit
/// gets a crust that is generated in Dart and needs no shader bundle, no
/// data-assets flag and no successful compile.
///
/// Same trick as the grass blade mask: generate pixels rather than ship a
/// texture, which also keeps the CC0 asset fence (L5) intact.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';

/// Cheap deterministic value noise. Seeded by hand so the crust is the
/// same every run — a pit that looked different each cast would read as
/// flicker.
double _hash(int x, int y, int seed) {
  var h = x * 374761393 + y * 668265263 + seed * 1274126177;
  h = (h ^ (h >> 13)) * 1274126177;
  return ((h ^ (h >> 16)) & 0x7fffffff) / 0x7fffffff;
}

double _valueNoise(double x, double y, int seed) {
  final xi = x.floor();
  final yi = y.floor();
  final xf = x - xi;
  final yf = y - yi;
  // Smoothstep the cell interpolation, or the crust reads as a grid.
  final u = xf * xf * (3 - 2 * xf);
  final v = yf * yf * (3 - 2 * yf);
  final a = _hash(xi, yi, seed);
  final b = _hash(xi + 1, yi, seed);
  final c = _hash(xi, yi + 1, seed);
  final d = _hash(xi + 1, yi + 1, seed);
  return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v;
}

double _fbm(double x, double y, int seed) {
  var sum = 0.0;
  var amplitude = 0.5;
  var frequency = 1.0;
  for (var octave = 0; octave < 4; octave++) {
    sum += _valueNoise(x * frequency, y * frequency, seed + octave) * amplitude;
    amplitude *= 0.5;
    frequency *= 2.0;
  }
  return sum;
}

/// RGBA pixels for a [size]×[size] lava crust, mapped over the pit's
/// disc. The rim cools to rock so the pool has an edge rather than
/// stopping dead.
Uint8List lavaCrustPixels(int size) {
  final pixels = Uint8List(size * size * 4);
  final center = (size - 1) / 2.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final u = x / size * 6.0;
      final v = y / size * 6.0;

      // Two fields crawling against each other: where they cross is
      // where the crust has split open.
      final flow = _fbm(u, v, 61);
      final churn = _fbm(u * 2.3 + 11, v * 2.3 - 7, 67);
      final molten = (flow * 0.65 + churn * 0.35).clamp(0.0, 1.0);

      // Distance to the rim, for the cooled edge.
      final dx = (x - center) / center;
      final dy = (y - center) / center;
      final radius = math.sqrt(dx * dx + dy * dy).clamp(0.0, 1.0);
      final rim = 1.0 - _smoothstep(0.62, 1.0, radius);

      // Channels: a narrow band of the noise is molten, the rest is rock.
      final veins = _smoothstep(0.46, 0.78, molten);
      final hot = _smoothstep(0.72, 0.95, molten);

      // Crust is near-black with a little warmth; the channels glow.
      // Blue stays near zero throughout — the same reason the fire keeps
      // it low, so nothing here can drift toward white.
      final r = (0.09 + veins * 1.05 + hot * 0.55).clamp(0.0, 1.0);
      final g = (0.05 + veins * 0.26 + hot * 0.42).clamp(0.0, 1.0);
      final b = (0.05 + veins * 0.03 + hot * 0.10).clamp(0.0, 1.0);

      final o = (y * size + x) * 4;
      pixels[o] = (r * rim * 255).round();
      pixels[o + 1] = (g * rim * 255).round();
      pixels[o + 2] = (b * rim * 255).round();
      pixels[o + 3] = 255;
    }
  }
  return pixels;
}

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

Texture2D? _crust;

/// The shared crust texture, built lazily on first use (needs the GPU
/// context, so every call site is already scene-gated).
Texture2D lavaCrustTexture() =>
    _crust ??= Texture2D.fromPixels(lavaCrustPixels(256), 256, 256);
