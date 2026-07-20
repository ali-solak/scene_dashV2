/// The blade's trail: a ribbon of light rebuilt every frame from where
/// the sword ACTUALLY IS.
///
/// The previous crescent was a fixed mesh spawned once per swing, sized
/// from the hitbox. It was honest about reach and completely wrong about
/// motion — a shape that appeared, sat there and faded, whatever the
/// blade did. This samples the sword node's world transform each frame
/// and stitches the samples into a strip, so the ribbon is the path the
/// weapon swept: it curves the way the animation curves, it is short when
/// the swing is slow and long when it whips, and it stops dead when the
/// blade does.
///
/// One `GeometryStorage.updatable` mesh, rebuilt in place — no
/// per-frame allocation, no entity churn.
library;

import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

/// How many samples the ribbon remembers. At a 60 Hz fixed step this is
/// the trail's length in frames — long enough to arc, short enough that
/// it reads as a whip rather than a scarf.
const int trailSamples = 14;

/// Where the blade's tip sits in the sword node's local space. The
/// weapons are authored with the blade running up +Y from the grip.
const double swordBladeLength = 1.35;

/// A sample of the blade in world space: the two ends of one rung of the
/// ribbon.
class _Rung {
  _Rung(this.hilt, this.tip);
  final Vector3 hilt;
  final Vector3 tip;
}

/// The live trail behind one blade. Owns its node and geometry.
///
/// The vertex count NEVER changes. An updatable geometry sizes its GPU
/// buffers from the arrays it is first given and grows only within that
/// spare capacity — feeding it a ribbon that starts at two rungs and
/// swells to fourteen overruns them and throws (`RangeError` out of
/// `_RingBufferStream.writeRange`). So every rebuild writes all
/// [trailSamples] rungs, and the ones that are not yet real collapse
/// onto the oldest live rung at zero alpha: degenerate triangles that
/// cost nothing and draw nothing.
class SwordTrail {
  SwordTrail._(this.node, this._geometry);

  final Node node;
  final MeshGeometry _geometry;

  /// Fixed-length ring of samples, oldest first. Entries at indices below
  /// `trailSamples - _live` are stale padding.
  final List<_Rung> _rungs = <_Rung>[];
  int _live = 0;

  /// Scratch buffers, reused every frame — the whole point of updatable
  /// storage is not allocating here.
  late final Float32List _positions = Float32List(trailSamples * 2 * 3);
  late final Float32List _colors = Float32List(trailSamples * 2 * 4);
  late final List<int> _indices = _buildIndices();

  /// Builds an empty trail node, ready to be added to the scene.
  factory SwordTrail.create() {
    final geometry = MeshGeometry.fromArrays(
      positions: Float32List(trailSamples * 2 * 3),
      colors: Float32List(trailSamples * 2 * 4),
      indices: _buildIndices(),
      storage: GeometryStorage.updatable,
    );
    // White base: the ribbon's colour lives entirely in its vertex
    // colours, so one material serves every tint.
    final material = UnlitMaterial()
      ..baseColorFactor = Vector4(1, 1, 1, 1)
      ..alphaMode = AlphaMode.blend;
    final node = Node(name: 'sword-trail')
      ..frustumCulled = false
      ..mesh = Mesh(geometry, material);
    node.visible = false;
    return SwordTrail._(node, geometry);
  }

  /// The strip's topology, which is the same every frame.
  static List<int> _buildIndices() {
    final indices = <int>[];
    for (var i = 0; i < trailSamples - 1; i++) {
      final a = i * 2;
      final b = a + 1;
      final d = a + 2;
      final e = a + 3;
      // Both windings: a translucent material is always back-face culled,
      // and a ribbon is seen from either side as the fighter turns.
      indices
        ..addAll([a, b, d, b, e, d])
        ..addAll([d, b, a, d, e, b]);
    }
    return indices;
  }

  /// Records where the blade is this frame. [swordWorld] is the sword
  /// node's `globalTransform`.
  void sample(Matrix4 swordWorld) {
    final rung = _Rung(
      swordWorld.transformed3(Vector3.zero()),
      swordWorld.transformed3(Vector3(0, swordBladeLength, 0)),
    );
    _rungs.add(rung);
    while (_rungs.length > trailSamples) {
      _rungs.removeAt(0);
    }
    if (_live < trailSamples) _live++;
  }

  /// Drops the oldest rung — how the ribbon retracts once the swing is
  /// over, instead of vanishing all at once.
  void retract() {
    if (_live > 0) _live--;
    if (_live == 0) _rungs.clear();
  }

  bool get isEmpty => _live < 2;

  /// Rewrites the strip from the samples, at a fixed vertex count.
  void rebuild(Vector4 tint) {
    node.visible = !isEmpty;
    if (isEmpty) return;

    // The live rungs sit at the END of the list; anything before them is
    // padding collapsed onto the oldest live sample.
    final firstLive = _rungs.length - _live;
    final oldest = _rungs[firstLive];

    var p = 0;
    var c = 0;
    for (var i = 0; i < trailSamples; i++) {
      final liveIndex = i - (trailSamples - _live);
      final real = liveIndex >= 0;
      final rung = real ? _rungs[firstLive + liveIndex] : oldest;

      _positions[p++] = rung.hilt.x;
      _positions[p++] = rung.hilt.y;
      _positions[p++] = rung.hilt.z;
      _positions[p++] = rung.tip.x;
      _positions[p++] = rung.tip.y;
      _positions[p++] = rung.tip.z;

      // Newest rung is the head of the trail and the brightest; the tail
      // fades out, and padding is fully transparent.
      final age = _live > 1 ? (liveIndex / (_live - 1)).clamp(0.0, 1.0) : 1.0;
      final head = real ? age * age : 0.0;
      for (var k = 0; k < 2; k++) {
        final towardTip = k == 1 ? 1.0 : 0.25;
        _colors[c++] = tint.x;
        _colors[c++] = tint.y;
        _colors[c++] = tint.z;
        _colors[c++] = tint.w * head * towardTip;
      }
    }

    _geometry.rebuild(
      positions: _positions,
      colors: _colors,
      indices: _indices,
    );
  }

  void clear() {
    _rungs.clear();
    _live = 0;
    node.visible = false;
  }
}
