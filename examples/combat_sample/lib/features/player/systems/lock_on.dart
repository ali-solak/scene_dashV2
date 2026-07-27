part of '../player.dart';

/// Target acquisition and the highlights that show it. Must install
/// after [installPlayerActions]: the exemption list below is by function
/// reference, so those systems have to exist first.
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
      // These systems use separate Fighter fields: this one writes the
      // stance, they read the attack phase.
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

/// Lock-on. [LockPressed] toggles: acquire the nearest living enemy in
/// [lockAcquireRange], or release. [LockCycled] steps to the next
/// candidate by angle (wrapping). The lock drops itself on target death
/// or a [lockBreakRange] break. [Fighter.stance] is derived here and read
/// everywhere else.
void lockOnSystem(World world) {
  final pressed = world.consumeAny<LockPressed>();
  final cycled = world.consumeAny<LockCycled>();
  final row = world
      .query3<Fighter, PlayerMotion, SceneTransform>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (player, fighter, _, transform) = row;
  final current = world.tryGet<Target>(player)?.entity;

  var held =
      current != null &&
          _isValidTarget(world, transform, current, lockBreakRange)
      ? current
      : null;

  if (pressed) {
    held = held != null
        ? null // toggle off
        : _acquireTarget(world, transform);
  } else if (cycled && held != null) {
    held = _nextTarget(world, transform, held);
  }

  if (held == null) {
    if (current != null) world.remove<Target>(player);
  } else if (held != current) {
    world.add(player, Target(held)); // re-add replaces
  }
  fighter.stance = held != null ? Stance.locked : Stance.free;
}

/// Finds the nearest lock target.
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
    } else if (bestBehind == null || candidate.distance < bestBehind.distance) {
      bestBehind = candidate;
    }
  }
  return (bestInView ?? bestBehind)?.entity;
}

/// Cycle (Q): the next candidate clockwise by angle, wrapping; [current]
/// keeps the lock when it is the only candidate left.
Entity _nextTarget(World world, SceneTransform player, Entity current) {
  final others =
      _lockCandidates(world, player).where((c) => c.entity != current).toList()
        ..sort((a, b) => a.angle.compareTo(b.angle));
  if (others.isEmpty) return current;
  final currentAngle = _angleTo(player, world, current);
  return others
      .firstWhere(
        (c) => c.angle > currentAngle,
        orElse: () => others.first, // wrap around
      )
      .entity;
}

final class _Candidate {
  const _Candidate(this.entity, this.distance, this.angle);
  final Entity entity;
  final double distance;
  final double angle;
}

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
    candidates.add(_Candidate(enemy, distance, math.atan2(dx, dz)));
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

double _angleTo(SceneTransform player, World world, Entity entity) {
  final transform = world.tryGet<SceneTransform>(entity);
  if (transform == null) return 0;
  return math.atan2(
    transform.translation.x - player.translation.x,
    transform.translation.z - player.translation.z,
  );
}

/// Updates enemy highlights.
///
/// The recursive node walk is the expensive part, so steady states (no
/// highlight, the static lock gold) write once and are remembered in
/// [EnemyHighlights]; only a telegraph's rising pulse rewrites per frame.
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

/// Last enemy highlight states.
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

// Helpers
