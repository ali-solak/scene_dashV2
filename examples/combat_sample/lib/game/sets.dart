/// Cross-feature system phases. Features join a phase with `inSet:`; the
/// composition root (`main`) declares the phase order once per schedule
/// (scene_game's pattern — plugins never reference each other's systems).
library;

import 'package:scene_dash_v2/scene_dash_v2.dart';

abstract final class GameSets {
  // fixedUpdate: the player moves, the barbarians answer (reading the
  // moved player), the machines transition, then resolution reads the
  // frame's edges. Cross-feature ordering lives ONLY in this sequence —
  // resolution never names another feature's systems.
  static const movement = SystemSet('game.movement');
  static const enemyMovement = SystemSet('game.enemyMovement');
  static const actions = SystemSet('game.actions');
  static const resolution = SystemSet('game.resolution');

  /// The wave director runs last: it counts who is still standing AFTER
  /// this step's damage has landed.
  static const waves = SystemSet('game.waves');

  // update: per-frame logic (camera rig, highlights, material tells).
  static const logic = SystemSet('game.logic');
}
