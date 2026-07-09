import 'package:flutter/widgets.dart';
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';

import 'game_scope.dart';
import 'scene_game.dart';

/// The minimal debug inspector: a plain, toggleable entity list — every
/// named entity's `debugDescribe` line. The data already exists; this
/// widget only renders it.
///
/// Cheap by construction: the lines are re-derived once per rendered frame
/// and the list only rebuilds when they changed. Named entities (carrying
/// [Name]) appear; anonymous entities are noise and are left out. Wrap it
/// in your own toggle/positioning chrome; it has no visual opinion beyond
/// a scrollable text column.
final class WorldInspector extends StatefulWidget {
  const WorldInspector({super.key, this.maxEntities = 200});

  /// Upper bound on listed entities.
  final int maxEntities;

  @override
  State<WorldInspector> createState() => _WorldInspectorState();
}

final class _WorldInspectorState extends State<WorldInspector> {
  WorldGame? _game;
  List<String> _lines = const <String>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = GameScope.of(context);
    if (identical(next, _game)) return;
    _game?.frameTick.removeListener(_onFrameTick);
    _game = next..frameTick.addListener(_onFrameTick);
    _lines = _describe();
  }

  @override
  void dispose() {
    _game?.frameTick.removeListener(_onFrameTick);
    super.dispose();
  }

  void _onFrameTick() {
    if (!mounted) return;
    final lines = _describe();
    if (_sameLines(lines, _lines)) return;
    setState(() => _lines = lines);
  }

  bool _sameLines(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<String> _describe() {
    final world = _game!.world;
    final names = world.ensureObjectStore<Name>();
    final lines = <String>[];
    for (var dense = 0; dense < names.length; dense++) {
      if (lines.length >= widget.maxEntities) {
        lines.add('… ${names.length - widget.maxEntities} more');
        break;
      }
      lines.add(
        world.debugDescribe(world.entities.resolve(names.entityIndexAt(dense))),
      );
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    // Self-contained: debug chrome gets dropped into arbitrary trees, so
    // provide the Directionality a bare host (no MaterialApp) lacks.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ListView.builder(
        itemCount: _lines.length,
        itemBuilder: (context, index) => Text(
          _lines[index],
          style: const TextStyle(fontSize: 11),
          softWrap: false,
        ),
      ),
    );
  }
}
