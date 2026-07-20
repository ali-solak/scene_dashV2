library;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Vector3, Vector4;

// --- Dimensions (world units; placements add 0.85–1.2 jitter on top) ---

const double _trunkHeight = 2.2;
const double _trunkBottomRadius = 0.3;
const double _trunkTopRadius = 0.2;
const double _coneHeight = 2.2;
const double _coneStep = 1.15;
const double _canopyBaseY = 1.6;
const List<double> _coneRadii = [2.0, 1.55, 1.1];

const double _rockRadius = 0.7;
const double _bushRadius = 0.55;

// --- LOD thresholds (fraction of viewport height; device-tunable) ---

const double _treeDetailScreenSize = 0.09;
const double _propDetailScreenSize = 0.08;
const double _lodBlendRange = 0.2;

/// Shared geometry + material pools for the clearing's dressing. Build once,
/// scene-side (geometry construction needs the GPU context).
class ForestKit {
  ForestKit._({
    required this.trunkHi,
    required this.trunkLo,
    required this.conesHi,
    required this.conesLo,
    required this.rockHi,
    required this.rockLo,
    required this.bushHi,
    required this.bushLo,
    required this.trunkMaterial,
    required this.canopyMaterials,
    required this.rockMaterial,
    required this.bushMaterial,
  });

  factory ForestKit.build() {
    PhysicallyBasedMaterial matte(double r, double g, double b) =>
        PhysicallyBasedMaterial()
          ..baseColorFactor = Vector4(r, g, b, 1)
          ..roughnessFactor = 1
          ..metallicFactor = 0;

    return ForestKit._(
      trunkHi: CylinderGeometry(
        bottomRadius: _trunkBottomRadius,
        topRadius: _trunkTopRadius,
        height: _trunkHeight,
        radialSegments: 10,
      ),
      trunkLo: CylinderGeometry(
        bottomRadius: _trunkBottomRadius,
        topRadius: _trunkTopRadius,
        height: _trunkHeight,
        radialSegments: 5,
      ),
      conesHi: [
        for (final radius in _coneRadii) _cone(radius, radialSegments: 10),
      ],
      conesLo: [
        for (final radius in _coneRadii) _cone(radius, radialSegments: 6),
      ],
      rockHi: IcosphereGeometry(radius: _rockRadius, subdivisions: 2),
      rockLo: IcosphereGeometry(radius: _rockRadius, subdivisions: 1),
      bushHi: IcosphereGeometry(radius: _bushRadius, subdivisions: 2),
      bushLo: IcosphereGeometry(radius: _bushRadius, subdivisions: 1),
      trunkMaterial: matte(0.36, 0.25, 0.16),
      // A few canopy tones so the ring reads as many trees, not one copy.
      canopyMaterials: [
        matte(0.20, 0.34, 0.15),
        matte(0.16, 0.30, 0.18),
        matte(0.25, 0.38, 0.14),
      ],
      rockMaterial: matte(0.45, 0.44, 0.42),
      bushMaterial: matte(0.18, 0.30, 0.14),
    );
  }

  static Geometry _cone(double radius, {required int radialSegments}) =>
      CylinderGeometry(
        bottomRadius: radius,
        topRadius: 0.02,
        height: _coneHeight,
        radialSegments: radialSegments,
        topCap: false,
      );

  final Geometry trunkHi, trunkLo;
  final List<Geometry> conesHi, conesLo;
  final Geometry rockHi, rockLo, bushHi, bushLo;
  final Material trunkMaterial;
  final List<Material> canopyMaterials;
  final Material rockMaterial;
  final Material bushMaterial;

  /// A stylized pine: LOD trunk + three stacked LOD cones. [variantRoll]
  /// picks the canopy tone.
  Node tree(double variantRoll) {
    final canopy =
        canopyMaterials[(variantRoll * canopyMaterials.length).floor() %
            canopyMaterials.length];
    final root = Node(name: 'tree');
    root.add(
      _lodNode(
        y: _trunkHeight / 2,
        hi: trunkHi,
        lo: trunkLo,
        material: trunkMaterial,
        detailScreenSize: _treeDetailScreenSize,
      ),
    );
    for (var i = 0; i < _coneRadii.length; i++) {
      root.add(
        _lodNode(
          y: _canopyBaseY + i * _coneStep + _coneHeight / 2,
          hi: conesHi[i],
          lo: conesLo[i],
          material: canopy,
          detailScreenSize: _treeDetailScreenSize,
        ),
      );
    }
    return root;
  }

  /// A boulder; [variantRoll] squashes it so no two read identical.
  Node rock(double variantRoll) {
    final squash = 0.6 + 0.4 * variantRoll;
    final node = _lodNode(
      y: _rockRadius * squash * 0.8,
      hi: rockHi,
      lo: rockLo,
      material: rockMaterial,
      detailScreenSize: _propDetailScreenSize,
    );
    node.localTransform = node.localTransform..scaleByDouble(1, squash, 1, 1);
    return Node(name: 'rock')..add(node);
  }

  Node bush(double variantRoll) {
    final squash = 0.55 + 0.25 * variantRoll;
    final node = _lodNode(
      y: _bushRadius * squash * 0.75,
      hi: bushHi,
      lo: bushLo,
      material: bushMaterial,
      detailScreenSize: _propDetailScreenSize,
    );
    node.localTransform = node.localTransform
      ..scaleByDouble(1.15, squash, 1.15, 1);
    return Node(name: 'bush')..add(node);
  }

  Node _lodNode({
    required double y,
    required Geometry hi,
    required Geometry lo,
    required Material material,
    required double detailScreenSize,
  }) {
    return Node(localTransform: Matrix4.translation(Vector3(0, y, 0)))
      ..addComponent(
        LodComponent([
          LodLevel(
            geometry: hi,
            material: material,
            screenSize: detailScreenSize,
          ),
          // screenSize 0: the low level never culls — a vanished tree
          // would open a hole in the treeline.
          LodLevel(geometry: lo, material: material, screenSize: 0),
        ], blendRange: _lodBlendRange),
      )
      ..shadowStatic = true;
  }
}
