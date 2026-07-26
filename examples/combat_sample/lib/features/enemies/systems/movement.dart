part of '../enemies.dart';

/// Pack locomotion: the per-phase steering, the knockback arc, and the
/// tumble a thrown body carries.
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

/// Barbarian locomotion, one fixed step at a time: approach closes in,
/// circle orbits at a breathing radius, everything from the telegraph on
/// is rooted (facing frozen from the swing so rolls beat committed arcs).
/// Death stops this controller; [launchPhysicsCorpse] hands the body to
/// Rapier after the hit reaction.
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
    // Sent flying (a wind blast): the arc owns them until they land.
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
    brawler.airborne = knockback?.airborne ?? false; // falls vs lies
    _applyFacingAndTumble(brawler, transform);
  });
}

/// The living brawler's per-phase steering: ground velocity out, facing
/// written in place. Everything from the telegraph on is rooted.
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

  var velocityX = 0.0;
  var velocityZ = 0.0;
  switch (brawler.phase.state) {
    case BrawlPhase.approach:
      velocityX = towardX * approachSpeed;
      velocityZ = towardZ * approachSpeed;
      brawler.facing = math.atan2(dx, dz);
    case BrawlPhase.circle:
      if (brawler.hasToken) {
        // The token holder closes in to strike range.
        velocityX = towardX * tokenCloseSpeed;
        velocityZ = towardZ * tokenCloseSpeed;
      } else {
        brawler.wobble += dt;
        final radiusTarget =
            circleRadius +
            circleWobbleAmplitude *
                math.sin(
                  brawler.wobbleSeed +
                      brawler.wobble * circleWobbleRate * 2 * math.pi,
                );
        // Tangential orbit plus a radial correction toward the target
        // radius.
        final tangentX = -towardZ * brawler.circleDirection;
        final tangentZ = towardX * brawler.circleDirection;
        final radial = (distance - radiusTarget).clamp(-1.0, 1.0);
        velocityX = tangentX * circleSpeed + towardX * radial * circleSpeed;
        velocityZ = tangentZ * circleSpeed + towardZ * radial * circleSpeed;
      }
      brawler.facing = math.atan2(dx, dz);
    case BrawlPhase.dodging:
      // Backward side roll.
      velocityX =
          (-towardX * dodgeBackWeight -
              towardZ * brawler.dodgeSign * dodgeSideWeight) *
          dodgeSpeed;
      velocityZ =
          (-towardZ * dodgeBackWeight +
              towardX * brawler.dodgeSign * dodgeSideWeight) *
          dodgeSpeed;
      brawler.facing = math.atan2(dx, dz);
    case BrawlPhase.telegraph:
      brawler.facing = math.atan2(dx, dz); // the tell tracks its mark
    case BrawlPhase.taunting:
      brawler.facing = math.atan2(dx, dz); // roots, but taunts at its mark
    case BrawlPhase.rising:
      break; // on the floor hauling itself up; no drift, no aim yet
    case BrawlPhase.swing ||
        BrawlPhase.recover ||
        BrawlPhase.staggered ||
        BrawlPhase.dying:
      break; // rooted, facing frozen
  }

  // Bogged down in a lava pit. Only the ground speed is mired; the
  // facing/aim above stay full, so it still tracks the player as it
  // wades, and a wind blast can still launch it.
  if (mired) {
    velocityX *= miredSpeedFactor;
    velocityZ *= miredSpeedFactor;
  }
  return (velocityX, velocityZ);
}

/// The one-way tip toward prone for a living wind-blast throw.
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

/// Yaw to the stored facing, then apply a living throw's tumble pitch.
void _applyFacingAndTumble(Brawler brawler, SceneTransform transform) {
  transform.rotation.setAxisAngle(_upAxis, brawler.facing);
  if (brawler.tumble != 0) {
    transform.rotation.setFrom(
      transform.rotation * Quaternion.axisAngle(_tumbleAxis, brawler.tumble),
    );
  }
}

final Vector3 _upAxis = Vector3(0, 1, 0);

/// Head over heels, not a flat spin.
final Vector3 _tumbleAxis = Vector3(1, 0, 0);
