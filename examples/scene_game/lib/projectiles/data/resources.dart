part of '../projectiles.dart';

/// The single charge-plasma emitter, owned by systems like the reticle:
/// `spawnChargePlasma` fills it (startup, scene-gated) and
/// `updateChargeVisuals` attaches it to the current player and throttles
/// its spawn rate with the charge. Fields stay null in headless worlds.
final class ChargePlasma {
  /// The emitter node, positioned at the muzzle orb offset; parented to
  /// the live player's root while a run is on.
  Node? node;

  /// The emitter's spawner; rate 0 while idle.
  fx.Spawner? spawner;
}

/// The single reused lock-on reticle: one [WidgetComponent] on one node,
/// repositioned onto the current target each frame — never one node per rock.
/// [model] bridges the ECS systems (writers) and [ReticleWidget] (painter).
final class LockOnReticle implements Disposable {
  Node? node;
  WidgetComponent? component;

  final ReticleModel model = ReticleModel();

  double opacity = 0;
  double charge01 = 0;
  bool locked = false;
  double firedFlash = 0;
  double impactFlash = 0;

  // Scratch basis vectors so per-frame billboarding allocates nothing.
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

  /// Places [node] at the target position facing [camera], mutating the node
  /// transform in place (no allocation).
  void billboardAt(double tx, double ty, double tz, Vector3 camera) {
    final n = node;
    if (n == null) return;
    _forward
      ..setValues(camera.x - tx, camera.y - ty, camera.z - tz)
      ..normalize();
    _worldUp.crossInto(_forward, _right);
    if (_right.length2 < 1e-6) {
      // Degenerate (camera directly above): fall back to world X.
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
    n.localTransform = n.localTransform;
    n.visible = true;
  }

  void hideNode() => node?.visible = false;

  void reset() {
    opacity = 0;
    charge01 = 0;
    locked = false;
    firedFlash = 0;
    impactFlash = 0;
    model.reset();
    hideNode();
  }

  /// The resource owns [model]; the widget does not dispose it. The
  /// framework calls this at game shutdown ([Disposable]).
  @override
  void dispose() => model.dispose();
}
