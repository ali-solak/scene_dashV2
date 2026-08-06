part of '../enemies.dart';

void installBrawlerMovement(GameBuilder game) {
  game.addSystem(
    Schedules.fixedUpdate,
    moveBrawlers,
    inSet: GameSets.enemyMovement,
    reads: const {Player, Enemy, Mired},
    writes: const {Brawler, SceneTransform, Knockback},
    runIf: inState(GameStatus.fighting),
  );
}

void moveBrawlers(World world) {
  final playerRow = world
      .query<SceneTransform>(require: const [Player])
      .firstOrNull;
  if (playerRow == null) return;
  final playerPosition = playerRow.$2.translation;
  final dt = world.dt;

  world.query2<Brawler, SceneTransform>(require: const [Enemy]).each((
    entity,
    brawler,
    transform,
  ) {
    if (brawler.phase.state == BrawlPhase.dying) {
      brawler.velocity.setZero();
      return;
    }
    if (world.expiryOf<Transforming>(entity) != null) {
      brawler.velocity.setZero();
      return;
    }

    final (velocityX, velocityZ) = _steer(
      brawler,
      transform,
      playerPosition,
      dt,
      mired: world.has<Mired>(entity),
    );
    brawler.velocity.setValues(velocityX, 0, velocityZ);

    final knockback = world.tryGet<Knockback>(entity);
    // Knockback owns airborne movement.
    if (knockback == null || !knockback.airborne) {
      transform.translation
        ..x += velocityX * dt
        ..z += velocityZ * dt;
    }
    if (knockback != null) {
      knockback.step(dt, transform.translation);
    } else {
      transform.translation.y = 0;
    }
    clampToArena(transform.translation);

    _advanceTumble(brawler, knockback, dt);
    brawler.downed = knockback?.incapacitated ?? false;
    brawler.airborne = knockback?.airborne ?? false;
    _applyFacingAndTumble(brawler, transform);
  });
}

(double, double) _steer(
  Brawler brawler,
  SceneTransform transform,
  Vector3 playerPosition,
  double dt, {
  required bool mired,
}) {
  final dx = playerPosition.x - transform.translation.x;
  final dz = playerPosition.z - transform.translation.z;
  final distance = math.sqrt(dx * dx + dz * dz).clamp(1e-6, double.infinity);
  final towardX = dx / distance;
  final towardZ = dz / distance;

  final tracksPlayer = switch (brawler.phase.state) {
    BrawlPhase.approach ||
    BrawlPhase.circle ||
    BrawlPhase.dodging ||
    BrawlPhase.telegraph ||
    BrawlPhase.taunting => true,
    _ => false,
  };
  if (tracksPlayer) brawler.facing = math.atan2(dx, dz);

  var (velocityX, velocityZ) = switch (brawler.phase.state) {
    BrawlPhase.approach => (towardX * approachSpeed, towardZ * approachSpeed),
    BrawlPhase.circle => _circleVelocity(
      brawler,
      distance,
      towardX,
      towardZ,
      dt,
    ),
    BrawlPhase.dodging => (
      (-towardX * dodgeBackWeight -
              towardZ * brawler.dodgeSign * dodgeSideWeight) *
          dodgeSpeed,
      (-towardZ * dodgeBackWeight +
              towardX * brawler.dodgeSign * dodgeSideWeight) *
          dodgeSpeed,
    ),
    _ => (0.0, 0.0),
  };

  if (mired) {
    velocityX *= miredSpeedFactor;
    velocityZ *= miredSpeedFactor;
  }
  return (velocityX, velocityZ);
}

(double, double) _circleVelocity(
  Brawler brawler,
  double distance,
  double towardX,
  double towardZ,
  double dt,
) {
  if (brawler.hasToken) {
    return (towardX * tokenCloseSpeed, towardZ * tokenCloseSpeed);
  }
  brawler.wobble += dt;
  final radius =
      circleRadius +
      circleWobbleAmplitude *
          math.sin(
            brawler.wobbleSeed +
                brawler.wobble * circleWobbleRate * 2 * math.pi,
          );
  final radial = (distance - radius).clamp(-1.0, 1.0);
  return (
    -towardZ * brawler.circleDirection * circleSpeed +
        towardX * radial * circleSpeed,
    towardX * brawler.circleDirection * circleSpeed +
        towardZ * radial * circleSpeed,
  );
}

void _advanceTumble(Brawler brawler, Knockback? knockback, double dt) {
  if (knockback != null && knockback.airborne) {
    brawler.tumble = towardProne(
      brawler.tumble,
      dt * (0.75 + brawler.wobbleSeed % 0.5),
      rate: airborneProneRate,
    );
  } else if (knockback != null && knockback.downed > 0) {
    brawler.tumble = towardProne(brawler.tumble, dt, rate: proneSettleRate);
  } else {
    brawler.tumble = 0;
  }
}

void _applyFacingAndTumble(Brawler brawler, SceneTransform transform) {
  transform.rotation.setAxisAngle(_upAxis, brawler.facing);
  if (brawler.tumble != 0) {
    transform.rotation.setFrom(
      transform.rotation * Quaternion.axisAngle(_tumbleAxis, brawler.tumble),
    );
  }
}

final Vector3 _upAxis = Vector3(0, 1, 0);

// Head over heels.
final Vector3 _tumbleAxis = Vector3(1, 0, 0);
