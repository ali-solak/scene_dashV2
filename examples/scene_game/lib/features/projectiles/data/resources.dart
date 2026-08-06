part of '../projectiles.dart';

final class ChargePlasmaEmitter {
  ChargePlasmaEmitter({required this.node, required this.spawner});

  final Node node;

  final fx.Spawner spawner;
}

final class LockOnReticle {
  LockOnReticle({required this.node, required this.model});

  final Node node;

  final ReticleModel model;

  double opacity = 0;
  double charge01 = 0;
  bool locked = false;
  double firedFlash = 0;
  double impactFlash = 0;

  // Scratch vectors avoid frame allocations.
  final Vector3 _forward = Vector3.zero();
  final Vector3 _right = Vector3.zero();
  final Vector3 _up = Vector3.zero();
  static final Vector3 _worldUp = Vector3(0, 1, 0);

  void flashFired() => firedFlash = 1;

  void flashImpact() => impactFlash = 1;

  void pushToModel() => model.update(
    opacity: opacity,
    charge01: charge01,
    locked: locked,
    firedFlash: firedFlash,
    impactFlash: impactFlash,
  );

  void billboardAt(double tx, double ty, double tz, Vector3 camera) {
    final n = node;
    _forward
      ..setValues(camera.x - tx, camera.y - ty, camera.z - tz)
      ..normalize();
    _worldUp.crossInto(_forward, _right);
    if (_right.length2 < 1e-6) {
      // Fall back when the camera is directly above.
      _right.setValues(1, 0, 0);
    }
    _right.normalize();
    _forward.crossInto(_right, _up);

    final s = n.localTransform.storage;
    s[0] = _right.x;
    s[1] = _right.y;
    s[2] = _right.z;
    s[3] = 0;
    s[4] = _up.x;
    s[5] = _up.y;
    s[6] = _up.z;
    s[7] = 0;
    s[8] = _forward.x;
    s[9] = _forward.y;
    s[10] = _forward.z;
    s[11] = 0;
    s[12] = tx;
    s[13] = ty;
    s[14] = tz;
    s[15] = 1;
    // Reassignment marks the transform dirty.
    n.localTransform = n.localTransform;
    n.visible = true;
  }

  void hideNode() => node.visible = false;

  void reset() {
    opacity = 0;
    charge01 = 0;
    locked = false;
    firedFlash = 0;
    impactFlash = 0;
    model.reset();
    hideNode();
  }

  void dispose() => model.dispose();
}
