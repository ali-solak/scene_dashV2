import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

import '../../common/actors.dart';
import '../../common/camera_rig.dart';
import '../../common/game_state.dart';
import '../../common/reactions.dart';
import '../../common/sets.dart';
import '../../common/widget_quad.dart';
import '../../fx/dash_dust.dart';
import '../../hud/damage_number_widget.dart';
import '../enemies/enemies.dart' show Enemy;

export '../../common/reactions.dart';

part 'data/components.dart';
part 'data/config.dart';
part 'data/resources.dart';
part 'systems/reactions.dart';
part 'systems/combo.dart';
part 'vfx/dashes.dart';
part 'vfx/damage_numbers.dart';

void installFeedback(GameBuilder game) {
  installReactions(game);
  installCombo(game);
  installDashFx(game);
  installDamageNumbers(game);
}
