part of '../rules.dart';

// Shared scratch avoids frame allocations.
final Vector3 _playerPos = Vector3.zero();
final Vector3 _rockPos = Vector3.zero();
final Vector3 _down = Vector3(0, -1, 0);
final Ray _groundRay = Ray.originDirection(Vector3.zero(), Vector3(0, -1, 0));

void evaluateGameRules(World world) {
  final player = world.query<NodeRef>(require: const [Player]).firstOrNull;
  if (player == null) return;
  final node = player.$2.node;
  node.globalTranslationInto(_playerPos);
  final pos = _playerPos;

  final game = world.resource<GameState>();
  game.addSurvival(world.dt);
  if (_fellOff(world, game, pos)) return;
  _resolveRockHits(world, player.$1, pos);
}

bool _fellOff(World world, GameState game, Vector3 position) {
  if (game.survived <= startupGrace) return false;
  world.debugDraw.ray(
    position,
    _down,
    groundProbeDistance,
    color: DebugColor.yellow,
  );
  _groundRay.origin.setFrom(position);
  final ground = world.physics.raycast(
    _groundRay,
    maxDistance: groundProbeDistance,
    includeFixed: true,
    includeKinematic: false,
    includeDynamic: false,
  );
  if (ground != null || position.y > playerFallLoseY) return false;
  game.recordLoss('You fell off the platform');
  world.setState(GameStatus.lost);
  return true;
}

void _resolveRockHits(World world, Entity player, Vector3 position) {
  world.debugDraw.sphere(
    position,
    playerCollisionRadius + hitPadding,
    color: DebugColor.red,
  );
  final knockback = world.single<PlayerKnockback>();
  // Shield state is fixed for this scan.
  final shielded = world.has<Shielded>(player);
  world.physics.overlapSphereEntities(
    world.resource<SceneNodeIndex>(),
    position,
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
        _deflectRock(world, hit.node, position, rockPos);
        _absorbHit(world, player);
        return true;
      }
      knockback.pushFromRock(playerPosition: position, rockPosition: rockPos);
      return false;
    },
  );
}

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
    dx = 0;
    dz = -1;
    len = 1;
  }
  final nx = dx / len;
  final nz = dz / len;
  final body = rockNode.getComponent<RigidBody>();
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
  spawnDeflectBurst(world, rockPos);
}

void playerView(World world) {
  final player = world.query<NodeRef>(require: const [Player]).firstOrNull;
  if (player == null) return;
  player.$2.node.globalTranslationInto(_playerPos);
  world.resource<CameraRig>().follow(_playerPos, world.dt);
}

void requestRestart(World world) {
  if (!world.consumeAny<RestartRequested>()) return;
  if (world.state<GameStatus>() != GameStatus.lost) return;
  world.setState(GameStatus.playing);
}

void startRun(World world) {
  world.resource<GameState>().reset();
  world.resource<CameraRig>().reset();
  world.clock.timeScale = 1;
}

void slowMotionOnLoss(World world) {
  world.clock.timeScale = loseSlowMoTimeScale;
}
