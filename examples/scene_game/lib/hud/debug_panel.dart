import 'package:material_ui/material_ui.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';

import '../features/player/player.dart';
import '../features/rocks/rocks.dart';

final class DebugSettings {
  DebugSettings({
    this.debugDraw = false,
    this.stats = false,
    this.inspector = false,
  });

  bool debugDraw;
  bool stats;
  bool inspector;

  (bool, bool, bool) get snapshot => (debugDraw, stats, inspector);
}

class DebugPanel extends StatelessWidget {
  const DebugPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final world = GameScope.of(context).world;
    final settings = world.resource<DebugSettings>();
    return WorldBuilder<(bool, bool, bool)>(
      select: (world) => world.resource<DebugSettings>().snapshot,
      builder: (context, _) {
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
                  onPressed: () => settings.stats = !settings.stats,
                ),
                const SizedBox(width: 8),
                _ToggleChip(
                  icon: Icons.grid_3x3,
                  semanticLabel: 'Toggle debug draw',
                  active: settings.debugDraw,
                  onPressed: () =>
                      settings.debugDraw = !settings.debugDraw,
                ),
                const SizedBox(width: 8),
                _ToggleChip(
                  icon: Icons.manage_search,
                  semanticLabel: 'Toggle inspector',
                  active: settings.inspector,
                  onPressed: () => settings.inspector = !settings.inspector,
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
                  world.query<NodeRef>(require: const [Rock]).count(),
              builder: (context, rocks) => Text('rocks: $rocks'),
            ),
            // The one watched entity, resolved through the world each
            // frame — no handle crosses into the tree; `absent` covers
            // death and respawn gaps in one place.
            EntityBuilder<NodeRef, String>.matching(
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
