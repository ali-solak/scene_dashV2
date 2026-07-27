part of '../decor.dart';

/// Leaf count.
const int _leafCount = 60;

/// Bounds for falling leaves.
const double _leafFieldRadius = 15;
const double _leafCeiling = 5.5;

/// Leaf fall speed range.
const double _fallSlowest = 0.35;
const double _fallFastest = 1.25;

/// How hard the constant ambient wind pushes a leaf sideways.
const double _windPush = 1.7;

/// Leaf tumble and sway.
const double _tumbleFastest = 2.2;
const double _swayAmplitude = 0.9;

/// Seconds a leaf takes to cross the column, which sets the spawn rate.
/// Must outlast the fall (ceiling / terminal speed) or they expire midair.
const double _leafLifetime = 6.5;

/// Terminal speed is gravity/drag, so these two are read together: 1.6 over
/// a drag of 1.6 falls at 1 m/s, which crosses the column in 5.5s.
const double _leafGravity = 1.6;

/// Leaf size.
const double _leafSize = 0.22;

/// Holds the emitter node so the feature owns something addressable.
final class LeafField {
  Node? node;
}
