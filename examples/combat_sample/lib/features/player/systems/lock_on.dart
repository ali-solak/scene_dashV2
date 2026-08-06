part of '../player.dart';

/// Installs targeting after player actions because exemptions use references.
void installLockOn(GameBuilder game) {
  game
    ..world.insert(EnemyHighlights())
    ..addSystem(
      Schedules.fixedUpdate,
      lockOnSystem,
      inSet: GameSets.actions,
      reads: const {
        Player,
        Enemy,
        Health,
        PlayerMotion,
        SceneTransform,
        Target,
      },
      writes: const {Fighter},
      after: const [fighterDriver],
      independentOf: const [spawnPlayerFx, updateBladeTrail, announceWindup],
      runIf: inState(GameStatus.fighting),
    )
    ..addSystem(
      Schedules.update,
      updateEnemyHighlights,
      inSet: GameSets.logic,
      reads: const {Player, Enemy, Target, Brawler, NodeRef},
      runIf: hasResource<Scene>(),
    );
}

void lockOnSystem(World world) {
  final pressed = world.consumeAny<LockPressed>();
  final cycled = world.consumeAny<LockCycled>();
  final row = world
      .query3<Fighter, PlayerMotion, SceneTransform>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (player, fighter, _, transform) = row;
  final current = world.tryGet<Target>(player)?.entity;

  var held = current;
  if (held != null && !_isValidTarget(world, transform, held, lockBreakRange)) {
    held = null;
  }

  if (pressed) {
    held = held == null ? _acquireTarget(world, transform) : null;
  } else if (cycled && held != null) {
    held = _nextTarget(world, transform, held);
  }

  if (held == null) {
    if (current != null) world.remove<Target>(player);
  } else if (held != current) {
    world.add(player, Target(held));
  }
  fighter.stance = held != null ? Stance.locked : Stance.free;
}

Entity? _acquireTarget(World world, SceneTransform player) {
  final cameraYaw = world.resource<CameraRig>().yaw;
  _Candidate? bestInView;
  _Candidate? bestBehind;
  for (final candidate in _lockCandidates(world, player)) {
    final inView =
        angleDifference(candidate.angle, cameraYaw).abs() <= math.pi / 2;
    if (inView) {
      if (bestInView == null || candidate.distance < bestInView.distance) {
        bestInView = candidate;
      }
      continue;
    }
    if (bestBehind == null || candidate.distance < bestBehind.distance) {
      bestBehind = candidate;
    }
  }
  return (bestInView ?? bestBehind)?.entity;
}

Entity _nextTarget(World world, SceneTransform player, Entity current) {
  final others =
      _lockCandidates(world, player).where((c) => c.entity != current).toList()
        ..sort((a, b) => a.angle.compareTo(b.angle));
  if (others.isEmpty) return current;
  final currentAngle = _angleTo(world, player, current);
  return others
      .firstWhere((c) => c.angle > currentAngle, orElse: () => others.first)
      .entity;
}

typedef _Candidate = ({Entity entity, double distance, double angle});

List<_Candidate> _lockCandidates(World world, SceneTransform player) {
  final candidates = <_Candidate>[];
  world.query2<Health, SceneTransform>(require: const [Enemy]).each((
    enemy,
    health,
    enemyTransform,
  ) {
    if (!health.alive) return;
    final dx = enemyTransform.translation.x - player.translation.x;
    final dz = enemyTransform.translation.z - player.translation.z;
    final distance = math.sqrt(dx * dx + dz * dz);
    if (distance > lockAcquireRange) return;
    candidates.add((
      entity: enemy,
      distance: distance,
      angle: math.atan2(dx, dz),
    ));
  });
  return candidates;
}

bool _isValidTarget(
  World world,
  SceneTransform player,
  Entity target,
  double range,
) {
  final health = world.tryGet<Health>(target);
  if (health == null || !health.alive) return false;
  final transform = world.tryGet<SceneTransform>(target);
  if (transform == null) return false;
  final dx = transform.translation.x - player.translation.x;
  final dz = transform.translation.z - player.translation.z;
  return dx * dx + dz * dz <= range * range;
}

SceneTransform? _targetTransform(World world, Entity player) {
  final target = world.tryGet<Target>(player);
  return target == null ? null : world.tryGet<SceneTransform>(target.entity);
}

double _angleTo(World world, SceneTransform player, Entity entity) {
  final transform = world.tryGet<SceneTransform>(entity);
  if (transform == null) return 0;
  return math.atan2(
    transform.translation.x - player.translation.x,
    transform.translation.z - player.translation.z,
  );
}

/// Updates highlights only when their steady state changes.
void updateEnemyHighlights(World world) {
  final player = world.entitiesWith(require: const [Player]).firstOrNull;
  final locked = player == null ? null : world.tryGet<Target>(player)?.entity;
  final applied = world.resource<EnemyHighlights>().applied;
  world.query2<Brawler, NodeRef>(require: const [Enemy]).each((
    enemy,
    brawler,
    ref,
  ) {
    if (brawler.phase.state == BrawlPhase.telegraph) {
      final tell = (brawler.phase.elapsed / telegraphSeconds).clamp(0.0, 1.0);
      applied[enemy.index] = EnemyHighlights.telegraph;
      _setHighlight(
        ref.node,
        Vector4(1.0, 0.45 - 0.25 * tell, 0.1, 0.35 + 0.65 * tell),
      );
      return;
    }
    final state = enemy == locked
        ? EnemyHighlights.locked
        : EnemyHighlights.none;
    if (applied[enemy.index] == state) return;
    applied[enemy.index] = state;
    _setHighlight(
      ref.node,
      state == EnemyHighlights.locked ? Vector4(1.0, 0.78, 0.25, 1.0) : null,
    );
  });
}

final class EnemyHighlights {
  static const int none = 0;
  static const int locked = 1;
  static const int telegraph = 2;

  final Map<int, int> applied = <int, int>{};
}

void _setHighlight(Node node, Vector4? color) {
  node.highlightColor = color;
  for (final child in node.children) {
    _setHighlight(child, color);
  }
}
