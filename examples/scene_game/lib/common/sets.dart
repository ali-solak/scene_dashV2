/// Cross-feature system phases. Features join a phase with `inSet:`; the
/// composition root (`main`) declares the phase order once per schedule.
/// This is the only place cross-feature ordering lives — plugins never
/// reference each other's systems to write `after:` edges.
library;

import 'package:scene_dash_v2/scene_dash_v2.dart';

abstract final class GameSets {
  // fixedPrePhysics: the player moves, then actions read the moved position.
  static const movement = SystemSet('game.movement');
  static const actions = SystemSet('game.actions');

  // update: feature logic settles (shield tick, collection), then the rules
  // evaluate the frame's outcome against it.
  static const logic = SystemSet('game.logic');
  static const rules = SystemSet('game.rules');
}
