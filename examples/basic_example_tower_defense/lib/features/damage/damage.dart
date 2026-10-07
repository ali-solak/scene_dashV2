library;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

import 'data/config.dart';

part 'data/components.dart';
part 'data/bundles.dart';
part 'systems/systems.dart';

void installDamage(GameBuilder game) {
  game
    ..configureEvent<DamageDealt>()
    ..configureEvent<Destroyed>()
    ..observe<HitFlash>(onAdd: flashOn, onRemove: flashOff)
    ..observe<Shield>(onAdd: attachBubble, onRemove: detachBubble)
    ..addSystem(Schedules.fixedUpdate, applyDamage)
    ..addSystem(Schedules.fixedUpdate, destroyDead, after: [applyDamage])
    ..addSystem(Schedules.fixedUpdate, rechargeShields)
    ..addSystem(Schedules.update, popOnDestroyed, runIf: hasEvents<Destroyed>())
    ..addSystem(Schedules.update, animatePops)
    ..addSystem(Schedules.update, showShields, runIf: hasResource<Scene>());
}
