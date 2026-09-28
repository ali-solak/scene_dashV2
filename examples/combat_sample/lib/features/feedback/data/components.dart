part of '../feedback.dart';

final class DamageNumber {
  DamageNumber({
    required this.origin,
    required this.drift,
    required this.opacity,
    required this.node,
  });

  final Vector3 origin;
  final Vector3 drift;
  final ValueNotifier<double> opacity;
  final Node node;
  double age = 0;
}
