import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Quaternion, Vector2, Vector3;

import '../enemies/enemies.dart' show Brawler, Enemy, Mired;
import '../../fx/barrier_visual.dart';
import '../../fx/burning_visual.dart';
import '../../fx/fire_gush.dart';
import '../../fx/lava_pit_visual.dart';
import '../../fx/wind_blast.dart';
import '../../common/actors.dart';
import '../../assets/character_assets.dart';
import '../../common/combat_math.dart';
import '../../common/game_state.dart';
import '../../common/score.dart';
import '../../common/sets.dart';
import '../player/player.dart'
    show
        CastLeap,
        HitLanded,
        Knockback,
        PlayerAnimator,
        PlayerMotion,
        windCastSeconds;
import '../world/data/assets.dart';

part 'data/components.dart';
part 'data/config.dart';
part 'data/resources.dart';
part 'systems/casting.dart';
part 'systems/effects.dart';
part 'systems/visuals.dart';

/// Installs the skills as three sub-features: what a cast does, what it
/// leaves behind, and what that looks like.
void installSkills(GameBuilder game) {
  installSkillCasting(game);
  installSkillEffects(game);
  installSkillVisuals(game);
}
