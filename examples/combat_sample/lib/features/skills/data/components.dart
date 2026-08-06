part of '../skills.dart';

final class PendingWindBlast {
  PendingWindBlast(this.power);

  final double power;
  double elapsed = 0;
}

final class Burning {
  Burning(this.damage);

  final double damage;
  double sinceTick = 0;
}

final class LavaPit {
  LavaPit(this.damage);

  final double damage;

  double sinceTick = 0;

  double elapsed = 0;
}

final class Barrier {
  Barrier(this.charges) : maxCharges = charges;

  int charges;
  final int maxCharges;
  double sinceBlock = double.infinity;
  final Vector3 hitFrom = Vector3(0, 0, 1);

  bool get spent => charges <= 0;

  bool absorb({Vector3? push}) {
    charges--;
    sinceBlock = 0;
    if (push != null && push.x * push.x + push.z * push.z > 1e-9) {
      // Keep the ripple on the shell equator.
      hitFrom
        ..setValues(-push.x, 0, -push.z)
        ..normalize();
    }
    return spent;
  }
}

final class BarrierVisual {
  BarrierVisual({required this.sphere, required this.material, this.arm});

  final Node sphere;

  final Material material;
  double elapsed = 0;
  final Node? arm;
}

final class BurnFlame {
  const BurnFlame(this.node);

  final Node node;
}
