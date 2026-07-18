import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../player/player.dart';
import '../rocks/rocks.dart';

/// App-shell debug switches: the gizmo overlay, the live-stats panel and
/// the inspector.
final class DebugSettings {
  const DebugSettings({
    this.gizmos = false,
    this.stats = false,
    this.inspector = false,
  });

  /// Draw the gizmo overlay (ground probe, hit radii). A true runtime
  /// toggle — the pools build on the first enabled frame and hide again
  /// when it goes off.
  final bool gizmos;

  /// Show the live-stats panel (rock count, player position).
  final bool stats;

  /// Show the inspector overlay (entities, resources, timings, events).
  final bool inspector;

  DebugSettings copyWith({bool? gizmos, bool? stats, bool? inspector}) =>
      DebugSettings(
        gizmos: gizmos ?? this.gizmos,
        stats: stats ?? this.stats,
        inspector: inspector ?? this.inspector,
      );
}

/// Cubit-as-resource (§1.10), the app-shell pattern: `main` constructs one
/// instance, hands it to the widget tree through `BlocProvider` *and*
/// inserts it into the world — widgets drive it with ordinary cubit
/// methods, and systems read `cubit.state` like any other resource. The
/// write path stays one-directional: UI → cubit → world. [Disposable] is
/// the whole teardown wiring: the framework disposes the resource at game
/// shutdown, so nothing closes the cubit by hand.
final class DebugCubit extends Cubit<DebugSettings> implements Disposable {
  DebugCubit([super.initial = const DebugSettings()]);

  void toggleGizmos() => emit(state.copyWith(gizmos: !state.gizmos));

  void toggleStats() => emit(state.copyWith(stats: !state.stats));

  void toggleInspector() =>
      emit(state.copyWith(inspector: !state.inspector));

  @override
  void dispose() => close();
}

/// The read half of the cubit-as-resource pattern: once per frame, apply
/// the app-shell choices to the world.
void applyDebugSettings(World world) {
  world.gizmos.enabled = world.resource<DebugCubit>().state.gizmos;
}

/// Two toggle chips and, when stats are on, a live panel selected straight
/// from the world — `WorldBuilder` for the aggregate, `EntityBuilder` for
/// the one watched entity. Each rebuilds only when its value changes.
class DebugPanel extends StatelessWidget {
  const DebugPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DebugCubit, DebugSettings>(
      builder: (context, settings) {
        final cubit = context.read<DebugCubit>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ToggleChip(
                  icon: Icons.monitor_heart_outlined,
                  semanticLabel: 'Toggle live stats',
                  active: settings.stats,
                  onPressed: cubit.toggleStats,
                ),
                const SizedBox(width: 8),
                _ToggleChip(
                  icon: Icons.grid_3x3,
                  semanticLabel: 'Toggle debug gizmos',
                  active: settings.gizmos,
                  onPressed: cubit.toggleGizmos,
                ),
                const SizedBox(width: 8),
                _ToggleChip(
                  icon: Icons.manage_search,
                  semanticLabel: 'Toggle inspector',
                  active: settings.inspector,
                  onPressed: cubit.toggleInspector,
                ),
              ],
            ),
            if (settings.stats) ...[
              const SizedBox(height: 8),
              const _LiveStats(),
            ],
          ],
        );
      },
    );
  }
}

class _LiveStats extends StatelessWidget {
  const _LiveStats();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white70, fontSize: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // An aggregate straight off the world.
            WorldBuilder<int>(
              select: (world) =>
                  world.query<SceneNode>(require: const [Rock]).count(),
              builder: (context, rocks) => Text('rocks: $rocks'),
            ),
            // The one watched entity, resolved through the world each
            // frame — no handle crosses into the tree; `absent` covers
            // death and respawn gaps in one place.
            EntityBuilder<SceneNode, String>.matching(
              require: const [Player],
              select: (binding) =>
                  binding.node.localTransform.storage[12].toStringAsFixed(1),
              builder: (context, x) => Text('player x: $x'),
              absent: const Text('player x: —'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.icon,
    required this.semanticLabel,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String semanticLabel;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: active ? Colors.white30 : Colors.black38,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white38),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? Colors.white : Colors.white54,
          ),
        ),
      ),
    );
  }
}
