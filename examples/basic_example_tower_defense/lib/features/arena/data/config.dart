library;

import 'package:vector_math/vector_math.dart' show Aabb3, Vector3, Vector4;

const double arenaHalfSize = 16;
const double pathWidth = 2.4;
const double pathMarkerThickness = 0.04;

const double pathClearance = pathWidth / 2 + 0.7;

const String groundNodeName = 'ground';

final Vector3 cameraEye = Vector3(0, 26, -22);

final Vector4 groundColor = Vector4(0.10, 0.12, 0.16, 1);
final Vector4 pathColor = Vector4(0.42, 0.34, 0.20, 1);

final List<Vector3> towerPath = [
  Vector3(-14, 0, -8),
  Vector3(6, 0, -8),
  Vector3(6, 0, 8),
  Vector3(-6, 0, 8),
  Vector3(-6, 0, 0),
  Vector3(14, 0, 0),
];

Aabb3 segmentBox(Vector3 a, Vector3 b, Vector3 growth) => Aabb3.minMax(a, a)
  ..hullPoint(b)
  ..min.sub(growth)
  ..max.add(growth);
