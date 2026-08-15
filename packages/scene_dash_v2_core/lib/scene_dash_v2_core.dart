/// Core ECS APIs.
library;

export 'src/diagnostics/app_diagnostics.dart' show AppDiagnostics;
export 'src/diagnostics/debug_describe.dart';
export 'src/diagnostics/name.dart';
export 'src/entity/entity.dart';
export 'src/entity/entity_registry.dart';
export 'src/input/axis_input.dart';
export 'src/input/button_input.dart';
export 'src/input/input_buffer.dart';
export 'src/resources/resources.dart';
// Used by SceneGame.boot and TestGame.headless.
export 'src/schedule/access_conflict.dart' show AccessConflictPolicy;
export 'src/schedule/run_conditions.dart';
export 'src/schedule/schedule_label.dart';
export 'src/schedule/schedules.dart';
export 'src/schedule/system_registration.dart' show RunCondition;
export 'src/schedule/system_set.dart';
export 'src/state/despawn_after.dart';
export 'src/state/states.dart'
    show CurrentState, DespawnOnExit, NextState, OnEnter, OnExit, inState;
export 'src/surface/game_builder.dart' show Feature, GameBuilder, WorldSystem;
export 'src/surface/observers.dart' show ComponentObserver, ObserverRegistry;
export 'src/surface/queries.dart';
export 'src/surface/spawning.dart' show OwnedBy, SpawnQueue;
export 'src/surface/tag.dart';
export 'src/surface/test_game.dart';
export 'src/surface/world_extensions.dart';
export 'src/time/fixed_time.dart';
export 'src/time/frame_time.dart';
export 'src/time/game_clock.dart';
export 'src/time/machine.dart';
export 'src/time/routine.dart';
export 'src/time/timers.dart';
export 'src/world/world.dart';
