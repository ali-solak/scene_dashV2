part of '../skills.dart';

/// What the effects look like: burn flames, the barrier bubble and its
/// mounted shield, and the lava pits' bodies and materials.
void installSkillVisuals(GameBuilder game) {
  game
    ..registerComponent<BurnFlame>()
    ..registerComponent<BarrierVisual>()
    ..addSystem(
      Schedules.update,
      attachLavaVisuals,
      inSet: GameSets.logic,
      reads: const {LavaPit, SceneTransform},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateBurnFlames,
      inSet: GameSets.logic,
      reads: const {Enemy, Burning, SceneNode},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateBarrierVisual,
      inSet: GameSets.logic,
      reads: const {Player, Barrier, SceneNode},
      runIf: hasResource<Scene>(),
    )
    ..addSystem(
      Schedules.update,
      updateLavaMaterials,
      inSet: GameSets.logic,
      reads: const {LavaPit, SceneNode},
      after: const [attachLavaVisuals],
      runIf: hasResource<Scene>(),
    );
}

/// Lights up whoever is burning and puts the fire out when the burn's
/// clock ends (a no-op headless). Driven off the presence of [Burning],
/// so a burn refreshed mid-fire never restarts the flame.
void updateBurnFlames(World world) {
  world.query<SceneNode>(require: const [Enemy]).each((entity, ref) {
    final burning = world.tryGet<Burning>(entity) != null;
    final flame = world.tryGet<BurnFlame>(entity);
    if (burning && flame == null) {
      final node = buildBurnFlame();
      ref.node.add(node);
      world.add(entity, BurnFlame(node));
    } else if (!burning && flame != null) {
      ref.node.remove(flame.node);
      world.remove<BurnFlame>(entity);
    }
  });
}

/// Raises and drops the light sphere (and the arm shield) with the
/// barrier itself, and drives the bubble's brightness from what is left
/// (a no-op headless). Driven off the presence of [Barrier]:
/// `applyDamage` can remove it anywhere, and the bubble must follow.
void updateBarrierVisual(World world) {
  final dt = world.dt;
  world.query<SceneNode>(require: const [Player]).each((entity, ref) {
    final barrier = world.tryGet<Barrier>(entity);
    final visual = world.tryGet<BarrierVisual>(entity);

    if (barrier == null) {
      if (visual == null) return;
      ref.node.remove(visual.sphere);
      // The shield hangs off an animated joint deep in the skeleton, not
      // off the node we added it under; detach is the only way back.
      visual.arm?.detach();
      world.remove<BarrierVisual>(entity);
      return;
    }

    var current = visual;
    if (current == null) {
      final built = buildBarrierSphere(
        radius: shieldRadius,
        height: shieldHeight,
        authored: world.hasResource<WorldAssets>()
            ? world.resource<WorldAssets>().barrierMaterial
            : null,
      );
      ref.node.add(built.node);
      current = BarrierVisual(
        sphere: built.node,
        material: built.material,
        arm: _mountShield(world, ref.node),
      );
      world.add(entity, current);
    }

    current.elapsed += dt;
    setBarrierCharge(
      current.material,
      time: current.elapsed,
      remaining: barrier.charges / barrier.maxCharges,
      // 1 on the frame of a block, decaying to 0 over the flash window.
      // Off the gameplay clock alone: adding this frame's dt would
      // double-count it, and `sinceBlock` starts at infinity so a fresh
      // barrier reads 0 here.
      flash: 1 - barrier.sinceBlock / shieldFlashSeconds,
      hitFrom: barrier.hitFrom,
    );
  });
}

/// Hangs the shield on the character's left hand slot, when there is a
/// character and a shield to hang. A clone per raise: the template is
/// shared, and the barrier can come and go many times in a run.
Node? _mountShield(World world, Node body) {
  if (!world.hasResource<CharacterAssets>()) return null;
  final template = world.resource<CharacterAssets>().shield;
  final slot = body.getChildByName('handslot.l');
  if (template == null || slot == null) return null;
  final shield = template.clone()
    // Stands the slab up and turns its face forward; the hand slot's own
    // frame puts it flat otherwise. See [shieldMountRotation].
    ..localTransform = Matrix4.compose(
      Vector3.zero(),
      shieldMountRotation,
      Vector3.all(1),
    );
  slot.add(shield);
  return shield;
}

/// Gives every fresh pit its crust and its embers (a no-op headless).
void attachLavaVisuals(World world) {
  final assets = world.hasResource<WorldAssets>()
      ? world.resource<WorldAssets>()
      : null;
  world.query2<LavaPit, SceneTransform>().each((entity, pit, at) {
    if (world.tryGet<SceneNode>(entity) != null) return;
    world.add(
      entity,
      SceneNode(
        buildLavaPitNode(
          material: assets?.lavaMaterial,
          center: Vector2(at.translation.x, at.translation.z),
        ),
      ),
    );
  });
}

/// Drives the crust's `time` and its swell-in/cool-down (L3: the material
/// follows the pit's clock, the pit never asks the material anything).
void updateLavaMaterials(World world) {
  world.query2<LavaPit, SceneNode>().each((entity, pit, ref) {
    final remaining = world.expiryOf<DespawnAfter>(entity) ?? lavaPitSeconds;
    // Swells open fast, then dims over its last second as it crusts over.
    final heat =
        (pit.elapsed / lavaPitOpenSeconds).clamp(0.0, 1.0) *
        (remaining / lavaPitCoolSeconds).clamp(0.0, 1.0);
    setLavaPitHeat(ref.node, time: pit.elapsed, heat: heat);
  });
}
