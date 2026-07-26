import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:scene_dash_v2_core/advanced.dart'
    show
        EntityDetailSnapshot,
        EntitySnapshot,
        EventChannelSnapshot,
        InspectorSnapshot,
        ResourceSnapshot,
        SnapshotCollector,
        SystemSnapshot;

/// Displays a live game inspector.
class InspectorOverlay extends StatefulWidget {
  const InspectorOverlay({
    super.key,
    required this.visible,
    this.pollInterval = const Duration(milliseconds: 250),
  });

  /// Whether the panel is shown.
  final bool visible;

  /// How often the overlay collects a fresh snapshot while visible.
  final Duration pollInterval;

  @override
  State<InspectorOverlay> createState() => _InspectorOverlayState();
}

class _InspectorOverlayState extends State<InspectorOverlay> {
  SnapshotCollector? _collector;
  InspectorSnapshot? _snapshot;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(InspectorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible || oldWidget.pollInterval != widget.pollInterval) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _refresh() {
    final collector = _collector;
    if (collector == null || !mounted) return;
    setState(() => _snapshot = collector.collect());
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) {
      _timer?.cancel();
      _timer = null;
      _snapshot = null;
      return const SizedBox.shrink();
    }
    final world = GameScope.of(context).world;
    var collector = _collector;
    if (collector == null || !identical(collector.world, world)) {
      collector = SnapshotCollector(world);
      _collector = collector;
      _snapshot = null;
    }
    // Show content immediately.
    final snapshot = _snapshot ??= collector.collect();
    _timer ??= Timer.periodic(widget.pollInterval, (_) => _refresh());
    return Align(
      alignment: Alignment.topRight,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: InspectorPanel(
            snapshot: snapshot,
            describe: collector.describeEntity,
          ),
        ),
      ),
    );
  }
}

enum _InspectorTab { entities, resources, systems, events }

/// Displays an inspector snapshot.
class InspectorPanel extends StatefulWidget {
  const InspectorPanel({
    super.key,
    required this.snapshot,
    required this.describe,
  });

  final InspectorSnapshot snapshot;

  /// Loads details for a selected entity.
  final EntityDetailSnapshot Function(int index, int generation) describe;

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  _InspectorTab _tab = _InspectorTab.entities;
  String _filter = '';
  EntityDetailSnapshot? _detail;
  bool _sortByMs = false;

  @override
  void didUpdateWidget(InspectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final detail = _detail;
    if (detail != null && !identical(oldWidget.snapshot, widget.snapshot)) {
      // Refresh the selected entity.
      _detail = widget.describe(detail.index, detail.generation);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340, maxHeight: 460),
      child: Material(
        color: const Color(0xF01B1B24),
        borderRadius: BorderRadius.circular(8),
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 12, color: Colors.white),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    const Text(
                      'Inspector',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${widget.snapshot.entityCount} entities',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  for (final tab in _InspectorTab.values)
                    _TabButton(
                      label: tab.name,
                      selected: _tab == tab,
                      onPressed: () => setState(() => _tab = tab),
                    ),
                ],
              ),
              const Divider(height: 1, color: Colors.white24),
              Flexible(child: _tabBody()),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the selected tab.
  Widget _tabBody() {
    final snapshot = widget.snapshot;
    switch (_tab) {
      case _InspectorTab.entities:
        final detail = _detail;
        if (detail != null) {
          return _EntityDetail(
            detail: detail,
            onBack: () => setState(() => _detail = null),
          );
        }
        return _EntityList(
          entities: snapshot.entities,
          filter: _filter,
          onFilterChanged: (value) => setState(() => _filter = value),
          onSelect: (index, generation) => setState(() {
            _detail = widget.describe(index, generation);
          }),
        );
      case _InspectorTab.resources:
        return _ResourceList(resources: snapshot.resources);
      case _InspectorTab.systems:
        return _SystemList(
          systems: snapshot.systems,
          sortByMs: _sortByMs,
          onToggleSort: () => setState(() => _sortByMs = !_sortByMs),
        );
      case _InspectorTab.events:
        return _EventList(events: snapshot.events);
    }
  }
}

String _entityTitle(int index, int generation, String? name) {
  final label = name == null ? '' : ' "$name"';
  return 'Entity($index v$generation)$label';
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 6),
          minimumSize: Size.zero,
          foregroundColor: selected ? Colors.amber : Colors.white70,
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}

class _EntityList extends StatelessWidget {
  const _EntityList({
    required this.entities,
    required this.filter,
    required this.onFilterChanged,
    required this.onSelect,
  });

  final List<EntitySnapshot> entities;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final void Function(int index, int generation) onSelect;

  @override
  Widget build(BuildContext context) {
    final needle = filter.toLowerCase();
    final matches = entities
        .where((e) => (e.name ?? '').toLowerCase().contains(needle))
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            key: const Key('inspector-filter'),
            style: const TextStyle(fontSize: 12, color: Colors.white),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'filter by Name',
              hintStyle: TextStyle(color: Colors.white38),
            ),
            onChanged: onFilterChanged,
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entity in matches)
                _Tile(
                  key: Key('inspector-entity-${entity.index}'),
                  title: _entityTitle(
                    entity.index,
                    entity.generation,
                    entity.name,
                  ),
                  subtitle: entity.componentTypes.join(', '),
                  onTap: () => onSelect(entity.index, entity.generation),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EntityDetail extends StatelessWidget {
  const _EntityDetail({required this.detail, required this.onBack});

  final EntityDetailSnapshot detail;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('inspector-detail-back'),
              icon: const Icon(
                Icons.arrow_back,
                size: 16,
                color: Colors.white70,
              ),
              onPressed: onBack,
            ),
            Expanded(
              child: Text(
                _entityTitle(detail.index, detail.generation, detail.name),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (detail.stale)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '<stale - despawned>',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            children: [
              for (final line in detail.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(line),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResourceList extends StatelessWidget {
  const _ResourceList({required this.resources});

  final List<ResourceSnapshot> resources;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        for (final resource in resources)
          _Tile(title: resource.type, subtitle: resource.value),
      ],
    );
  }
}

class _SystemList extends StatelessWidget {
  const _SystemList({
    required this.systems,
    required this.sortByMs,
    required this.onToggleSort,
  });

  final List<SystemSnapshot> systems;
  final bool sortByMs;
  final VoidCallback onToggleSort;

  @override
  Widget build(BuildContext context) {
    final ordered = systems.toList();
    if (sortByMs) {
      ordered.sort((a, b) => b.lastMs.compareTo(a.lastMs));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const Key('inspector-sort-ms'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size.zero,
              foregroundColor: sortByMs ? Colors.amber : Colors.white70,
            ),
            onPressed: onToggleSort,
            icon: const Icon(Icons.sort, size: 14),
            label: const Text('by ms', style: TextStyle(fontSize: 11)),
          ),
        ),
        if (ordered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'No timings - enable AppDiagnostics(profileSystems: true).',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final system in ordered)
                _Tile(
                  title: system.label,
                  subtitle: system.schedule,
                  trailing:
                      '${system.lastMs.toStringAsFixed(2)} ms '
                      '(avg ${system.averageMs.toStringAsFixed(2)})',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList({required this.events});

  final List<EventChannelSnapshot> events;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: [
        for (final event in events)
          _Tile(
            title: event.type,
            subtitle: 'pending ${event.pending}',
            trailing: event.readerLagged ? 'reader lagging' : null,
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    final tail = trailing;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, overflow: TextOverflow.ellipsis),
                  if (sub != null && sub.isNotEmpty)
                    Text(
                      sub,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
            if (tail != null)
              Text(
                tail,
                style: const TextStyle(fontSize: 10, color: Colors.amberAccent),
              ),
          ],
        ),
      ),
    );
  }
}
