library;

import 'package:flutter_scene/scene.dart' show CatmullRomPath;
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

const double boardHalfSize = 18;
const double boardThickness = 1.6;
const double pathWidth = 2.2;
const double pathClearance = pathWidth / 2 + 0.6;

const String groundNodeName = 'ground';

final Vector3 cameraEye = Vector3(-24, 26, -24);
const double viewWidth = 54;
const double viewHeight = 36;
final Vector3 sunDirection = Vector3(-0.35, -1.0, 0.55);

final List<Vector3> pathPoints = [
  Vector3(-15, 0, -14),
  Vector3(-4, 0, -14),
  Vector3(2, 0, -8),
  Vector3(-4, 0, -2),
  Vector3(-12, 0, 2),
  Vector3(-12, 0, 10),
  Vector3(-3, 0, 13),
  Vector3(4, 0, 6),
  Vector3(9, 0, -2),
  Vector3(14, 0, -6),
  Vector3(14, 0, 6),
  Vector3(10, 0, 14),
];

final List<Vector3> route = CatmullRomPath(pathPoints)
    .sample(96, evenlySpaced: true);

enum DecorKind { tree, rock, pond }

final class const Decor(
  final DecorKind kind,
  final double x,
  final double z,
  final double radius,
);

const List<Decor> decor = [
  Decor(DecorKind.pond, -10, -7, 2.6),
  Decor(DecorKind.tree, 13, -14, 0.9),
  Decor(DecorKind.tree, 15.5, -11.5, 1.1),
  Decor(DecorKind.tree, 10.5, -16, 0.8),
  Decor(DecorKind.tree, -15, 15, 1.1),
  Decor(DecorKind.tree, -12.5, 16, 0.8),
  Decor(DecorKind.tree, -16, 12, 0.9),
  Decor(DecorKind.tree, 3, 16, 1.0),
  Decor(DecorKind.tree, -16, -3, 0.9),
  Decor(DecorKind.rock, 6, -14, 1.2),
  Decor(DecorKind.rock, 16.5, 11, 1.0),
  Decor(DecorKind.rock, -6, 6.5, 0.9),
];

final Vector4 grassColor = Vector4(0.30, 0.46, 0.27, 1);
final Vector4 cliffColor = Vector4(0.36, 0.27, 0.20, 1);
final Vector4 roadColor = Vector4(0.78, 0.66, 0.45, 1);
final Vector4 leafColor = Vector4(0.18, 0.40, 0.22, 1);
final Vector4 trunkColor = Vector4(0.40, 0.26, 0.16, 1);
final Vector4 rockColor = Vector4(0.52, 0.52, 0.56, 1);
final Vector4 waterColor = Vector4(0.20, 0.45, 0.70, 1);
final Vector4 portalGlow = Vector4(1.6, 0.4, 2.2, 1);
final Vector4 coreGlow = Vector4(0.4, 1.8, 2.4, 1);
