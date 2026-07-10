/// This surface runs the internal pipeline: the sparse-set stores, the
/// schedule graph and its adapters, the arity query classes the record
/// surface wraps, the deferred command buffer the structural verbs ride on,
/// and the scene-free frame dispatcher ([EcsFrameLoop]) that `TestGame` and
/// the integration driver both delegate to.
// WorldRecordQueries is hidden here: this tier exports the classic
// ClassicWorldQueries extension, which owns the same query2/3/4 names for
// migrated code, and Dart rejects a use site that sees both. Import the
// main library (optionally with `hide ClassicWorldQueries`) to use the
// record surface alongside this tier.
library;

export 'scene_dash_v2_core.dart' hide WorldRecordQueries;
export 'src/app/app.dart';
export 'src/app/app_builder.dart';
export 'src/app/plugin.dart';
export 'src/commands/bundle.dart';
export 'src/commands/commands.dart';
export 'src/commands/entity_commands.dart';
export 'src/diagnostics/app_diagnostics.dart';
// system_profiler.dart includes system_timing.dart as a part, so exporting it
// also exports SystemTiming.
export 'src/diagnostics/system_profiler.dart';
export 'src/events/event_channel.dart'
    show EventChannel, EventReader, EventWriter;
export 'src/loop/ecs_frame_loop.dart';
export 'src/query/entity_query.dart';
export 'src/query/query_1.dart';
export 'src/query/query_2.dart';
export 'src/query/query_3.dart';
export 'src/query/query_4.dart';
export 'src/query/single.dart';
export 'src/query/world_queries.dart';
export 'src/schedule/access_conflict.dart';
export 'src/schedule/system_descriptor.dart';
export 'src/schedule/system_label.dart';
export 'src/schedule/system_ref.dart';
export 'src/state/states.dart' show StateScheduleLabel;
export 'src/storage/component_store.dart';
export 'src/storage/object_store.dart';
export 'src/storage/store_registry.dart';
export 'src/storage/tag_store.dart';
export 'src/surface/game_builder.dart' show EventCursorHost;
export 'src/system/system_access.dart';
export 'src/system/system_adapter.dart';
