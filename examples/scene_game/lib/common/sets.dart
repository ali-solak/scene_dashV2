library;

import 'package:scene_dash_v2/scene_dash_v2.dart';

abstract final class GameSets {
  static const movement = SystemSet('game.movement');
  static const actions = SystemSet('game.actions');

  static const logic = SystemSet('game.logic');
  static const rules = SystemSet('game.rules');
}
