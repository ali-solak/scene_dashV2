library;

import 'dart:ui' show Offset, Size;

import 'package:flutter_scene/scene.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart'
    show Aabb3, Matrix4, Vector3, Vector4;

import 'data/config.dart';
part 'data/bundles.dart';
part 'systems/systems.dart';

void installArena(GameBuilder game) =>
    game.addSystem(Schedules.startup, spawnArena, runIf: hasResource<Scene>());
