import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Quaternion, Vector3, Vector4;

import '../../common/actors.dart';
import '../../common/camera_rig.dart';
import '../../common/combat_math.dart';
import '../../assets/character_assets.dart';
import '../../common/game_state.dart';
import '../../common/physics_layers.dart';
import '../../common/sets.dart';
import '../../fx/dash_dust.dart';
import '../../hud/health_bar_widget.dart';
import '../world/data/arena.dart';
import '../world/data/config.dart' show characterModelYaw, characterScale;
import 'package:flutter_scene/physics.dart';

export '../../common/actors.dart' show Health;

part 'animation/animator.dart';
part 'data/components.dart';
part 'data/config.dart';
part 'data/bundles.dart';
part 'systems/brain.dart';
part 'systems/movement.dart';
part 'systems/death.dart';
part 'systems/visuals.dart';

/// Installs enemies.
void installEnemies(GameBuilder game) {
  game
    ..registerTag<Enemy>()
    ..registerComponent<Health>()
    ..registerComponent<Knockback>()
    ..registerComponent<Brawler>()
    ..registerComponent<Mired>();
  installBrawlBrain(game);
  installBrawlerMovement(game);
  installEnemyDeath(game);
  installEnemyVisuals(game);
}
