part of '../enemies.dart';

const List<String> _flailBones = [
  'upperarm.l',
  'lowerarm.l',
  'upperarm.r',
  'lowerarm.r',
  'upperleg.l',
  'lowerleg.l',
  'upperleg.r',
  'lowerleg.r',
];

/// Small spring-driven limb motion over the frozen hit pose.
final class LimbFlail {
  LimbFlail({
    required int limbCount,
    this.body,
    this.knockback,
    required this.seed,
    required this.impactKick,
    required double kickStrength,
  }) : angles = Float64List(limbCount),
       velocities = Float64List(limbCount) {
    _resetImpactTracking();
    _kick(kickStrength, seed);
  }

  RapierRigidBody? body;
  Knockback? knockback;
  double seed;
  double impactKick;
  final Float64List angles;
  final Float64List velocities;

  double previousVerticalVelocity = 0;
  bool wasAirborne = false;
  bool impacted = false;
  _LimbFlailDriver? _driver;

  void launch({
    RapierRigidBody? body,
    Knockback? knockback,
    required double seed,
    required double kickStrength,
    required double impactKick,
  }) {
    this.body = body;
    this.knockback = knockback;
    this.seed = seed;
    this.impactKick = impactKick;
    impacted = false;
    _resetImpactTracking();
    _kick(kickStrength, seed);
  }

  void _kick(double strength, double salt) {
    for (var i = 0; i < velocities.length; i++) {
      final hash = math.sin(salt * 12.9898 + i * 78.233) * 43758.5453;
      final random = hash - hash.floorToDouble();
      final distal = i.isOdd ? 1.15 : 0.9;
      velocities[i] +=
          strength *
          (0.65 + random * 0.35) *
          distal *
          (random > 0.5 ? 1 : -1);
    }
  }

  void _detectImpact() {
    if (impacted) return;
    final rigidBody = body;
    if (rigidBody != null) {
      if (rigidBody.nativeHandle == null) return;
      final verticalVelocity = rigidBody.readNativeLinearVelocity().y;
      if (previousVerticalVelocity < -flailImpactMinFallSpeed &&
          verticalVelocity > -0.5) {
        _impact();
      }
      previousVerticalVelocity = verticalVelocity;
      return;
    }

    final launch = knockback;
    if (launch == null) return;
    if (wasAirborne && !launch.airborne) {
      _impact();
    }
    wasAirborne = launch.airborne;
  }

  void _impact() {
    impacted = true;
    _kick(impactKick, seed + 19.7);
  }

  void _resetImpactTracking() {
    previousVerticalVelocity = body?.linearVelocity.y ?? 0;
    wasAirborne = knockback?.airborne ?? false;
  }

  void _advance(double deltaSeconds) {
    _detectImpact();
    final dt = math.min(deltaSeconds, 1 / 30);
    for (var i = 0; i < angles.length; i++) {
      var velocity = velocities[i];
      var angle = angles[i];
      velocity += (-flailStiffness * angle - flailDamping * velocity) * dt;
      angle = (angle + velocity * dt)
          .clamp(-flailMaxAngle, flailMaxAngle)
          .toDouble();
      velocities[i] = velocity;
      angles[i] = angle;
    }
  }
}

final class _LimbFlailDriver extends Component {
  _LimbFlailDriver(this.flail, this.bones, this.axes);

  final LimbFlail flail;
  final List<Node> bones;
  final List<Vector3> axes;

  @override
  void update(double deltaSeconds) {
    flail._advance(deltaSeconds);
    for (var i = 0; i < bones.length; i++) {
      final angle = flail.angles[i];
      if (angle.abs() < 1e-4) continue;
      bones[i].localTransform.multiply(
        Matrix4.compose(
          Vector3.zero(),
          Quaternion.axisAngle(axes[i], angle),
          _flailUnitScale,
        ),
      );
      bones[i].markTransformDirty();
    }
  }
}

void _detachLimbFlail(World world, Entity entity, LimbFlail flail) {
  final driver = flail._driver;
  if (driver != null && driver.isAttached) {
    driver.node.removeComponent(driver);
  }
}

LimbFlail? _buildLimbFlail(
  World world,
  Entity entity,
  Node sceneRoot, {
  RapierRigidBody? body,
  Knockback? knockback,
  required double seed,
  required double kickStrength,
  required double impactKick,
}) {
  final wrapper =
      sceneRoot.getChildByName('enemy-model') ??
      sceneRoot.getChildByName('player-model');
  if (wrapper == null || wrapper.children.isEmpty) return null;
  final model = wrapper.children.first;
  if (model.children.isEmpty) return null;

  final bones = <Node>[];
  final axes = <Vector3>[];
  for (var i = 0; i < _flailBones.length; i++) {
    final bone = model.getChildByName(_flailBones[i]);
    if (bone == null) return null;
    bones.add(bone);
    final axisAngle = seed * 4.7 + i * 2.17;
    axes.add(Vector3(math.cos(axisAngle), 0, math.sin(axisAngle)));
  }

  final flail = LimbFlail(
    limbCount: bones.length,
    body: body,
    knockback: knockback,
    seed: seed,
    kickStrength: kickStrength,
    impactKick: impactKick,
  );
  // The parent's animation player writes the base pose first.
  final driver = _LimbFlailDriver(flail, bones, axes);
  flail._driver = driver;
  world.resource<SceneCommands>().attach(model.children.first, driver);
  return flail;
}

void _triggerLimbFlail(
  World world,
  Entity entity, {
  RapierRigidBody? body,
  Knockback? knockback,
  required double seed,
  required double kickStrength,
  required double impactKick,
}) {
  final existing = world.tryGet<LimbFlail>(entity);
  if (existing != null) {
    existing.launch(
      body: body,
      knockback: knockback,
      seed: seed,
      kickStrength: kickStrength,
      impactKick: impactKick,
    );
    return;
  }

  final ref = world.tryGet<SceneNode>(entity);
  if (ref == null) return;
  final flail = _buildLimbFlail(
    world,
    entity,
    ref.node,
    body: body,
    knockback: knockback,
    seed: seed,
    kickStrength: kickStrength,
    impactKick: impactKick,
  );
  if (flail != null) world.add(entity, flail);
}

/// Adds stronger limb follow-through to a living ballistic launch.
void triggerAirborneFlail(
  World world,
  Entity entity,
  Knockback knockback,
  Vector3 impulse,
) {
  final lift = impulse.y.abs();
  final seed = impulse.x * 0.31 + impulse.y * 0.73 + impulse.z * 1.17;
  final kickStrength = flailKick + lift * airborneFlailKickPerLift;
  final impactKick = flailImpactKick + lift * airborneFlailImpactPerLift;
  _triggerLimbFlail(
    world,
    entity,
    knockback: knockback,
    seed: seed,
    kickStrength: kickStrength,
    impactKick: impactKick,
  );
}

final Vector3 _flailUnitScale = Vector3(1, 1, 1);
