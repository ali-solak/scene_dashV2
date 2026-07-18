part of '../rules.dart';

// Reused scratch state — systems run sequentially, so sharing is safe.
final Vector3 _playerPos = Vector3.zero();
final Vector3 _rockPos = Vector3.zero();
final Vector3 _down = Vector3(0, -1, 0);
final Ray _groundRay = Ray.originDirection(Vector3.zero(), Vector3(0, -1, 0));

/// Evaluates the lose condition (no ground below) and rock contacts each
/// frame.
void evaluateGameRules(World world) {
  final player = world.query<SceneNode>(require: const [Player]).firstOrNull;
  if (player == null) return;
  final node = player.$2.node;
  node.globalTranslationInto(_playerPos);
  final pos = _playerPos;

  final game = world.resource<GameState>();
  game.addSurvival(world.dt);

  if (game.survived > startupGrace) {
    world.gizmos.ray(pos, _down, groundProbeDistance, color: GizmoColor.yellow);
    _groundRay.origin.setFrom(pos);
    final ground = world.physics.raycast(
      _groundRay,
      maxDistance: groundProbeDistance,
      includeFixed: true,
      includeKinematic: false,
      includeDynamic: false,
    );
    if (ground == null && pos.y <= playerFallLoseY) {
      game.recordLoss('You fell off the platform');
      world.setState(GameStatus.lost);
      return;
    }
  }

  world.gizmos.sphere(
    pos,
    playerCollisionRadius + hitPadding,
    color: GizmoColor.red,
  );
  final playerEntity = player.$1;
  final knockback = world.single<PlayerKnockback>();
  // Captured once so the shield protects against every rock this frame,
  // even if deflecting one drains the remaining time to zero (the removal
  // is deferred anyway — presence holds until the boundary).
  final shielded = world.has<Shielded>(playerEntity);
  // The entity query re-checks the rock layer result-side and skips unbound
  // nodes, so no manual collider classification is needed here.
  world.physics.overlapSphereEntities(
    world.resource<SceneNodeIndex>(),
    pos,
    playerCollisionRadius + hitPadding,
    layerMask: PhysicsLayers.rock,
    includeFixed: false,
    includeKinematic: false,
    includeDynamic: true,
    includeTriggers: false,
    (entity, hit) {
      hit.node.globalTranslationInto(_rockPos);
      final rockPos = _rockPos;
      if (shielded) {
        _deflectRock(world, hit.node, pos, rockPos);
        _absorbHit(world, playerEntity);
        return true; // deflect every overlapping rock this frame
      }
      knockback.pushFromRock(playerPosition: pos, rockPosition: rockPos);
      return false; // one unshielded hit is enough — stop scanning
    },
  );
}

/// Deflecting a rock consumes shield time: re-add [Shielded] with the
/// reduced deadline (a refresh, S4), or remove it when the cost exceeds
/// what is left.
void _absorbHit(World world, Entity player) {
  final remaining = world.expiryOf<Shielded>(player);
  if (remaining == null) return;
  final next = remaining - shieldDeflectTimeCost;
  if (next <= 0) {
    world.remove<Shielded>(player);
  } else {
    world.add(player, const Shielded(), removeAfter: next);
  }
}

/// Throws a rock up and away from the player.
void _deflectRock(
  World world,
  Node rockNode,
  Vector3 playerPos,
  Vector3 rockPos,
) {
  var dx = rockPos.x - playerPos.x;
  var dz = rockPos.z - playerPos.z;
  var len = math.sqrt(dx * dx + dz * dz);
  if (len < 1e-4) {
    // Centres overlap: push uphill (-Z) rather than dividing by zero.
    dx = 0;
    dz = -1;
    len = 1;
  }
  final nx = dx / len;
  final nz = dz / len;
  final body = rockNode.getComponent<RapierRigidBody>();
  if (body != null) {
    body
      ..linearVelocity = Vector3(
        nx * shieldDeflectOutward,
        shieldDeflectUp,
        nz * shieldDeflectOutward,
      )
      ..angularVelocity = Vector3(
        shieldDeflectSpin,
        0,
        nx.sign * shieldDeflectSpin,
      );
  }
  // Deferred spawn of a run-scoped burst entity — safe inside the scan.
  spawnDeflectBurst(world, rockPos);
}

/// Camera follow: observes the latest player state after the rules pass.
void playerView(World world) {
  final player = world.query<SceneNode>(require: const [Player]).firstOrNull;
  if (player == null) return;
  player.$2.node.globalTranslationInto(_playerPos);
  world.resource<CameraRig>().follow(_playerPos, world.dt);
}

/// Consumes the restart intent: while lost, a restart request transitions
/// back to [GameStatus.playing]; [startRun] then does the actual reset in
/// `OnEnter(GameStatus.playing)`. Runs every frame in `frameStart`, so it
/// never lags the event retention window.
void requestRestart(World world) {
  if (!world.consumeAny<RestartRequested>()) return;
  if (world.state<GameStatus>() != GameStatus.lost) return;
  world.setState(GameStatus.playing);
}

/// Starts a run clean. Registered in `OnEnter(GameStatus.playing)`, so it
/// runs once at startup and again on every restart.
///
/// Rules only resets what it owns — the run clock, the camera, and the
/// game clock (undoing [slowMotionOnLoss]). Every feature resets its own
/// state in its own `OnEnter(GameStatus.playing)` system, and run-scoped
/// entities (rocks, projectiles, pickups) carry
/// `DespawnOnExit(GameStatus.playing)` in their bundles, so the transition
/// itself sweeps them.
void startRun(World world) {
  world.resource<GameState>().reset();
  world.resource<CameraRig>().reset();
  world.clock.timeScale = 1;
}

/// Losing drops the world into slow motion: physics, particles and the
/// camera drift behind the game-over panel while the HUD (frame-time)
/// stays crisp — the clock's whole-world guarantee, exercised.
void slowMotionOnLoss(World world) {
  world.clock.timeScale = loseSlowMoTimeScale;
}
