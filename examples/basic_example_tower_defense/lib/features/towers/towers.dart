library;

import 'dart:ui' show Offset, Size;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart'
    show Matrix4, Vector2, Vector3, Vector4;

import '../../common/game_state.dart';
import '../arena/arena.dart' show onDecor, onTowerPath;
import '../arena/data/config.dart' show groundNodeName;
import '../creeps/creeps.dart' show Creep;
import '../damage/damage.dart';
import '../rules/rules.dart' show Gold;
import 'data/config.dart';

part 'data/components.dart';
part 'data/bundles.dart';
part 'systems/systems.dart';

void installTowers(GameBuilder game) {
  game
    ..registerComponent<Tower>()
    ..registerComponent<Gun>()
    ..registerComponent<Pulser>()
    ..registerTag<ShieldEmitter>()
    ..registerComponent<TowerBeam>()
    ..registerComponent<PulseRing>()
    ..registerComponent<TowerGhost>()
    ..configureEvent<PlaceTowerRequested>()
    ..world.insert(BoardPointer())
    ..world.insert(BuildChoice())
    ..addSystem(Schedules.startup, spawnGhost, runIf: hasResource<Scene>())
    ..addSystem(
      Schedules.fixedUpdate,
      placeTowers,
      runIf: hasEvents<PlaceTowerRequested>().and(hasResource<Scene>()),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      fireGuns,
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(
      Schedules.fixedUpdate,
      firePulses,
      runIf: inState(GameStatus.playing),
    )
    ..addSystem(Schedules.fixedUpdate, projectShields)
    ..addSystem(Schedules.update, animateBeams, runIf: hasResource<Scene>())
    ..addSystem(Schedules.update, animateRings, runIf: hasResource<Scene>())
    ..addSystem(
      Schedules.update,
      previewPlacement,
      runIf: hasResource<Scene>(),
    );
}
