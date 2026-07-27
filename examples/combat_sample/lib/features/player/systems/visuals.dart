part of '../player.dart';

/// The knight's model, its animation mapper, and the i-frame ghost.
void installPlayerVisuals(GameBuilder game) {
  game
    ..registerComponent<PlayerAnimator>()
    ..addSystem(
      Schedules.update,
      attachPlayerVisuals,
      inSet: GameSets.logic,
      reads: const {Player},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updatePlayerAnimation,
      inSet: GameSets.logic,
      reads: const {Player, Fighter, PlayerMotion},
      writes: const {PlayerAnimator},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updatePlayerGhost,
      inSet: GameSets.logic,
      reads: const {Player, Fighter, NodeRef, Knockback},
      runIf: hasResource<Scene>(),
    );
}

/// Attaches the player model or fallback capsule.
void attachPlayerVisuals(World world) {
  final player = world.entitiesWith(require: const [Player]).firstOrNull;
  if (player == null) return;
  if (world.tryGet<NodeRef>(player) != null) return;

  if (world.hasResource<CharacterAssets>()) {
    final assets = world.resource<CharacterAssets>();
    final model = assets.knight;
    final weapon = assets.sword?.clone();
    if (weapon != null) {
      model.getChildByName('handslot.r')?.add(weapon);
    }
    final wrapper = Node(
      name: 'player-model',
      localTransform: Matrix4.compose(
        Vector3.zero(),
        Quaternion.axisAngle(Vector3(0, 1, 0), characterModelYaw),
        Vector3.all(characterScale),
      ),
    )..add(model);
    world.add(player, NodeRef(Node(name: 'player')..add(wrapper)));
    world.add(player, buildPlayerAnimator(assets, model));
    if (weapon != null) {
      // Rides a node at the blade tip; points are recorded in world space,
      // so the ribbon hangs where the blade has been.
      final trail = TrailComponent(
        width: bladeTrailWidth,
        lifetime: bladeTrailSeconds,
        colorOverTrail: lightTrailFade,
      );
      weapon.add(
        Node(
          name: 'blade-tip',
          localTransform: Matrix4.translation(Vector3(0, swordBladeLength, 0)),
        )..addComponent(trail),
      );
      world.add(player, BladeTrail(trail));
    }
    return;
  }

  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = Vector4(0.16, 0.42, 0.85, 1)
    ..roughnessFactor = 0.6;
  final root = Node(name: 'player')
    ..add(
      Node(
          localTransform: Matrix4.translation(
            Vector3(0, playerCapsuleHeight / 2 + playerCapsuleRadius, 0),
          ),
        )
        ..mesh = Mesh(
          CapsuleGeometry(
            radius: playerCapsuleRadius,
            height: playerCapsuleHeight,
          ),
          material,
        ),
    )
    ..add(
      Node(
        localTransform: Matrix4.translation(
          Vector3(0, 1.35, playerCapsuleRadius + 0.1),
        ),
      )..mesh = Mesh(CuboidGeometry(Vector3(0.14, 0.14, 0.3)), material),
    );
  world.add(player, NodeRef(root));
}

/// Updates player animation.
void updatePlayerAnimation(World world) {
  final dt = world.dt;
  world
      .query3<Fighter, PlayerMotion, PlayerAnimator>(require: const [Player])
      .each((entity, fighter, motion, animator) {
        animator.update(fighter, motion, dt);
      });
}

/// Shows a cyan outline while the player is invulnerable.
void updatePlayerGhost(World world) {
  final row = world
      .query2<Fighter, NodeRef>(require: const [Player])
      .firstOrNull;
  if (row == null) return;
  final (entity, fighter, ref) = row;
  final launched = world.tryGet<Knockback>(entity)?.incapacitated ?? false;
  _setHighlight(
    ref.node,
    fighter.iFramed || launched ? Vector4(0.45, 0.9, 1.0, 0.9) : null,
  );
}
