part of '../feedback.dart';

final class ComboMeter {
  int hits = 0;
  int best = 0;
  double sinceHit = double.infinity;

  void land() {
    hits++;
    sinceHit = 0;
    if (hits > best) best = hits;
  }

  void drop() => hits = 0;

  void reset() {
    hits = 0;
    best = 0;
    sinceHit = double.infinity;
  }
}
