import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:flutter_scene/physics.dart' show PhysicsWorld;
import 'package:vector_math/vector_math.dart'
    show Matrix4, Quaternion, Ray, Vector3, Vector4;

import '../enemies/enemies.dart'
    show Enemy, Brawler, BrawlPhase, telegraphSeconds;
import '../../fx/dash_dust.dart';
import '../../common/actors.dart';
import '../../common/camera.dart';
import '../../common/light_channels.dart';
import '../../common/physics_layers.dart';
import '../../common/camera_rig.dart';
import '../../common/combat_math.dart';
import '../../assets/character_assets.dart';
import '../../common/game_state.dart';
import '../../common/inputs.dart';
import '../../common/sets.dart';
import '../world/data/arena.dart';
import '../world/data/config.dart' show characterModelYaw, characterScale;
import 'combat/combat.dart';

export '../../common/actors.dart';
export 'combat/combat.dart';

part 'animation/animator.dart';
part 'data/components.dart';
part 'data/config.dart';
part 'data/bundles.dart';
part 'systems/lifecycle.dart';
part 'systems/motion.dart';
part 'systems/actions.dart';
part 'systems/lock_on.dart';
part 'systems/camera.dart';
part 'systems/visuals.dart';

/// Installs the player.
void installPlayer(GameBuilder game) {
  game
    ..registerTag<Player>()
    ..registerComponent<Fighter>()
    ..registerComponent<PlayerMotion>()
    ..registerComponent<Knockback>()
    ..registerComponent<Target>()
    ..registerComponent<BladeTrail>();
  installPlayerLifecycle(game);
  installPlayerMotion(game);
  installPlayerActions(game);
  installLockOn(game);
  installPlayerCamera(game);
  installPlayerVisuals(game);
}
