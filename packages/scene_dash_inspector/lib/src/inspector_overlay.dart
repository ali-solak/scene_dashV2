import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:scene_dash_v2_core/advanced.dart'
    show EntityDetailSnapshot, InspectorSnapshot, SnapshotCollector;

/// A toggleable, phone-usable inspector panel for a `Stack` (I4).
///
/// ```dart
/// Stack(children: [
///   GameView(...),
///   InspectorOverlay(visible: showInspector),
/// ])
/// ```
///
/// Resolves the game through [GameScope] and polls the core snapshot
/// boundary on [pollInterval] (default 4 Hz) while [visible]; hidden it
/// renders nothing, runs no timer and collects nothing. Read-only by
/// design: it consumes [InspectorSnapshot]s only and never touches the
/// world directly.
class InspectorOverlay extends StatefulWidget {
  const InspectorOverlay({
    super.key,
    required this.visible,
    this.pollInterval = const Duration(milliseconds: 250),
  });

  /// Whether the panel is shown (and polling). Wire it to your debug
  /// toggle.
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
    // First frame after becoming visible: collect synchronously so the
    // panel has content; the timer refreshes from then on.
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

/// The snapshot-driven panel behind [InspectorOverlay]: tabs for
/// entities (filter by `Name` substring, tap for detail), resources,
/// system timings (sortable by ms) and event channels.
///
/// Takes a fixed [snapshot] plus a [describe] callback — invoked only
/// when an entity is selected, keeping detail collection lazy (I2). Its
/// only input is snapshot data, which is what lets widget tests drive it
/// without a game and keeps the I1 boundary honest.
class InspectorPanel extends StatefulWidget {
  const InspectorPanel({
    super.key,
    required this.snapshot,
    required this.describe,
  });

  final InspectorSnapshot snapshot;

  /// Detail provider for a selected entity — `SnapshotCollector
  /// .describeEntity` in the overlay, a fake in tests.
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
      // A fresh snapshot arrived while a detail view is open: re-describe
      // the same selection so the values stay live (still detail-lazy —
      // only the selected entity is rendered).
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
                    _tabButton(tab, tab.name),
                ],
              ),
              const Divider(height: 1, color: Colors.white24),
              Flexible(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabButton(_InspectorTab tab, String label) {
    final selected = _tab == tab;
    return Expanded(
      child: TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 6),
          minimumSize: Size.zero,
          foregroundColor: selected ? Colors.amber : Colors.white70,
        ),
        onPressed: () => setState(() => _tab = tab),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }

  Widget _body() {
    switch (_tab) {
      case _InspectorTab.entities:
        final detail = _detail;
        return detail == null ? _entityList() : _entityDetail(detail);
      case _InspectorTab.resources:
        return _resourceList();
      case _InspectorTab.systems:
        return _systemList();
      case _InspectorTab.events:
        return _eventList();
    }
  }

  Widget _entityList() {
    final filter = _filter.toLowerCase();
    final entities = widget.snapshot.entities
        .where((e) => (e.name ?? '').toLowerCase().contains(filter))
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
            onChanged: (value) => setState(() => _filter = value),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entity in entities)
                _tile(
                  key: Key('inspector-entity-${entity.index}'),
                  title: _entityTitle(entity.index, entity.generation,
                      entity.name),
                  subtitle: entity.componentTypes.join(', '),
                  onTap: () => setState(() {
                    _detail =
                        widget.describe(entity.index, entity.generation);
                  }),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _entityDetail(EntityDetailSnapshot detail) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('inspector-detail-back'),
              icon: const Icon(Icons.arrow_back,
                  size: 16, color: Colors.white70),
              onPressed: () => setState(() => _detail = null),
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
            child: Text('<stale — despawned>',
                style: TextStyle(color: Colors.white54)),
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

  Widget _resourceList() {
    return ListView(
      shrinkWrap: true,
      children: [
        for (final resource in widget.snapshot.resources)
          _tile(title: resource.type, subtitle: resource.value),
      ],
    );
  }

  Widget _systemList() {
    final systems = widget.snapshot.systems.toList();
    if (_sortByMs) {
      systems.sort((a, b) => b.lastMs.compareTo(a.lastMs));
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
              foregroundColor: _sortByMs ? Colors.amber : Colors.white70,
            ),
            onPressed: () => setState(() => _sortByMs = !_sortByMs),
            icon: const Icon(Icons.sort, size: 14),
            label: const Text('by ms', style: TextStyle(fontSize: 11)),
          ),
        ),
        if (systems.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'No timings — enable AppDiagnostics(profileSystems: true).',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final system in systems)
                _tile(
                  title: system.label,
                  subtitle: system.schedule,
                  trailing: '${system.lastMs.toStringAsFixed(2)} ms '
                      '(avg ${system.averageMs.toStringAsFixed(2)})',
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _eventList() {
    return ListView(
      shrinkWrap: true,
      children: [
        for (final event in widget.snapshot.events)
          _tile(
            title: event.type,
            subtitle: 'pending ${event.pending}',
            trailing: event.readerLagged ? 'reader lagging' : null,
          ),
      ],
    );
  }

  static String _entityTitle(int index, int generation, String? name) {
    final label = name == null ? '' : ' "$name"';
    return 'Entity($index v$generation)$label';
  }

  Widget _tile({
    Key? key,
    required String title,
    String? subtitle,
    String? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      key: key,
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
                  if (subtitle != null && subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.white54),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style:
                    const TextStyle(fontSize: 10, color: Colors.amberAccent),
              ),
          ],
        ),
      ),
    );
  }
}
