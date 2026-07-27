part of '../decor.dart';

/// Leaf count.
const int _leafCount = 60;

/// Bounds for falling leaves.
const double _leafFieldRadius = 15;
const double _leafCeiling = 5.5;

/// Leaf fall speed range.
const double _fallSlowest = 0.35;
const double _fallFastest = 1.25;

const double _windPush = 0.5;

/// Leaf tumble and sway.
const double _tumbleFastest = 2.2;

const double _leafLifetime = 6.5;

const double _leafGravity = 1.6;

const double _leafSize = 0.22;

final class LeafField {
  Node? node;
}
