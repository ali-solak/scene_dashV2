import 'dart:math' as math;

import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import '../enemies/enemies.dart';
import '../../fx/impact_burst.dart';
import '../../common/camera_rig.dart';
import '../../common/combat_math.dart';
import '../../common/game_state.dart';
import '../../common/score.dart';
import '../../common/sets.dart';
import '../player/player.dart';
import '../skills/skills.dart';
import '../world/data/config.dart'
    show windCalmStrength, windEaseRate, windGustStrength;
import '../world/data/resources.dart' show WindState;

part 'data/config.dart';
part 'systems/flow.dart';
part 'systems/combat.dart';

/// Installs the rules as two sub-features: the run's flow, and the hit
/// resolution every fighter's swing goes through.
void installRules(GameBuilder game) {
  game
    ..registerComponent<DespawnAfter>()
    ..registerComponent<DespawnOnExit>();
  installRunFlow(game);
  installHitResolution(game);
}
