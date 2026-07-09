/// Spatial UI: real widgets at entities' projected screen positions —
/// enemy health bars, floating damage numbers, interaction prompts.
///
/// A [WorldOverlay] hosts [WorldAnchor] (one entity, one child) and
/// [WorldAnchors] (one child per entity carrying a type) entries. Per-frame
/// positioning is a [Flow] delegate driven by the game's `frameTick`:
/// transforms only — repaint, no rebuild, no layout. The camera is an
/// explicit parameter (D4) — the very object or builder you hand your
/// `SceneView` — so there is no hidden wiring, no publication step, and
/// nothing to forget. Membership (anchors appearing/disappearing as
/// entities spawn and despawn) is store-revision–driven, so frames where
/// nothing spawned rebuild nothing.
///
/// Contract: the overlay covers the same box as the `SceneView` (stack
/// them with `StackFit.expand`) — the projection is derived from the
/// overlay's own size.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart' show Camera;
import 'package:scene_dash_v2_core/advanced.dart' show ComponentStore;
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

import 'game_scope.dart';
import 'scene_game.dart';
import 'scene_node.dart';
import 'scene_transform.dart';

/// Positions [child] at [entity]'s projected screen position (plus a
/// world-space [offset]), centered on the point. Must be a direct child of
/// a [WorldOverlay]. The entity's position comes from its mounted node's
/// global transform when it has a [SceneNode], else its [SceneTransform];
/// while the entity is dead or has neither, the child is hidden in place.
final class WorldAnchor extends StatelessWidget {
  const WorldAnchor({
    super.key,
    required this.entity,
    this.offset,
    required this.child,
  });

  /// The entity to follow.
  final Entity entity;

  /// World-space offset from the entity's position (e.g. above the head).
  final Vector3? offset;

  /// The widget rendered at the projected position.
  final Widget child;

  @override
  Widget build(BuildContext context) => throw FlutterError(
        'WorldAnchor must be a direct child of a WorldOverlay, which '
        'interprets it (like Positioned inside Stack).',
      );
}

/// The auto variant of [WorldAnchor]: one [builder]-made child per entity
/// currently carrying [T] (a tag or component type), added and removed as
/// entities spawn and despawn — enemy health bars in one widget:
///
/// ```dart
/// WorldOverlay(camera: rigCamera, children: [
///   WorldAnchors<EnemyTag>(
///     offsetY: 2.2,
///     builder: (context, entity) => EnemyHealthBar(entity),
///   ),
/// ])
/// ```
///
/// [T] must have a registered store (tags always do after
/// `registerTag<T>()`). Must be a direct child of a [WorldOverlay].
final class WorldAnchors<T extends Object> extends StatelessWidget {
  const WorldAnchors({super.key, this.offsetY = 0, required this.builder});

  /// World-space Y offset above each entity's position.
  final double offsetY;

  /// Builds the anchored widget for one matching entity.
  final Widget Function(BuildContext context, Entity entity) builder;

  ComponentStore _store(World world) {
    if (!world.stores.isRegistered(T)) {
      throw FlutterError(
        'WorldAnchors<$T>: no store is registered for $T. Register it at '
        'install time (registerTag<$T>() / registerComponent<$T>()) or '
        'anchor to a type the game actually spawns.',
      );
    }
    return world.stores.require(T);
  }

  @override
  Widget build(BuildContext context) => throw FlutterError(
        'WorldAnchors must be a direct child of a WorldOverlay, which '
        'interprets it (like Positioned inside Stack).',
      );
}

/// One resolved anchor: where to read the position and which flow child it
/// positions.
final class _AnchorSlot {
  final Entity entity;
  final double offsetX, offsetY, offsetZ;

  _AnchorSlot(this.entity, Vector3? offset)
      : offsetX = offset?.x ?? 0,
        offsetY = offset?.y ?? 0,
        offsetZ = offset?.z ?? 0;

  _AnchorSlot.above(this.entity, this.offsetY)
      : offsetX = 0,
        offsetZ = 0;
}

/// Hosts world-anchored widgets over the scene; see the library docs for
/// the mechanism, the explicit-camera rule and the sizing contract.
final class WorldOverlay extends StatefulWidget {
  /// Positions [children] with [camera] or [cameraBuilder] — exactly one,
  /// and the same one you hand `SceneView`.
  const WorldOverlay({
    super.key,
    this.camera,
    this.cameraBuilder,
    required this.children,
  }) : assert(
         (camera != null) ^ (cameraBuilder != null),
         'WorldOverlay needs exactly one of camera or cameraBuilder — pass '
         'the same one your SceneView renders with.',
       );

  /// The fixed camera the scene renders with.
  final Camera? camera;

  /// The per-frame camera builder the scene renders with. Rig-style
  /// builders return one mutated camera, which is what the overlay reads.
  final Camera Function(Duration elapsed)? cameraBuilder;

  /// [WorldAnchor] and [WorldAnchors] entries.
  final List<Widget> children;

  @override
  State<WorldOverlay> createState() => _WorldOverlayState();
}

final class _WorldOverlayState extends State<WorldOverlay> {
  WorldGame? _game;

  /// Store revisions backing each [WorldAnchors] entry at the last build,
  /// parallel to `widget.children`; -1 for plain anchors.
  List<int> _revisions = const <int>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = GameScope.of(context);
    if (identical(next, _game)) return;
    _game?.frameTick.removeListener(_onFrameTick);
    _game = next..frameTick.addListener(_onFrameTick);
  }

  @override
  void dispose() {
    _game?.frameTick.removeListener(_onFrameTick);
    super.dispose();
  }

  /// Membership check only — positions repaint through the flow delegate's
  /// own `repaint` listenable without touching the widget tree.
  void _onFrameTick() {
    if (!mounted) return;
    final world = _game!.world;
    final children = widget.children;
    if (_revisions.length != children.length) {
      setState(() {});
      return;
    }
    for (var i = 0; i < children.length; i++) {
      final expected = _revisions[i];
      if (expected < 0) continue;
      final child = children[i];
      if (child is! WorldAnchors) continue;
      if (child._store(world).revision != expected) {
        setState(() {});
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = GameScope.of(context);
    final world = game.world;
    final slots = <_AnchorSlot>[];
    final flowChildren = <Widget>[];
    final revisions = <int>[];
    for (final child in widget.children) {
      switch (child) {
        case final WorldAnchor anchor:
          slots.add(_AnchorSlot(anchor.entity, anchor.offset));
          flowChildren.add(anchor.child);
          revisions.add(-1);
        case final WorldAnchors anchors:
          final store = anchors._store(world);
          revisions.add(store.revision);
          for (var dense = 0; dense < store.length; dense++) {
            final entity = world.entities.resolve(store.entityIndexAt(dense));
            slots.add(_AnchorSlot.above(entity, anchors.offsetY));
            flowChildren.add(anchors.builder(context, entity));
          }
        default:
          throw FlutterError(
            'WorldOverlay children must be WorldAnchor or WorldAnchors; '
            'got ${child.runtimeType}. Wrap plain UI in a WorldAnchor or '
            'put it in a Stack beside the overlay.',
          );
      }
    }
    _revisions = revisions;
    return Flow(
      delegate: _AnchorFlowDelegate(
        game,
        widget.camera,
        widget.cameraBuilder,
        slots,
        repaint: game.frameTick,
      ),
      children: flowChildren,
    );
  }
}

final class _AnchorFlowDelegate extends FlowDelegate {
  final WorldGame _game;
  final Camera? _camera;
  final Camera Function(Duration elapsed)? _cameraBuilder;
  final List<_AnchorSlot> _slots;
  final Vector4 _scratch = Vector4.zero();

  _AnchorFlowDelegate(
    this._game,
    this._camera,
    this._cameraBuilder,
    this._slots, {
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      constraints.loosen();

  @override
  void paintChildren(FlowPaintingContext context) {
    final camera = _camera ?? _cameraBuilder?.call(Duration.zero);
    if (camera == null) {
      throw FlutterError(
        'WorldOverlay has no camera to project with: the camera parameter '
        'resolved to null. Pass the camera (or cameraBuilder) you hand '
        'your SceneView.',
      );
    }
    final view = camera.getViewTransform(context.size);
    final world = _game.world;
    for (var i = 0; i < _slots.length; i++) {
      final slot = _slots[i];
      final position = _positionOf(world, slot);
      if (position == null) continue; // dead or bodiless: hidden this frame
      final v = _scratch
        ..setValues(
          position.x + slot.offsetX,
          position.y + slot.offsetY,
          position.z + slot.offsetZ,
          1,
        );
      view.transform(v);
      if (v.w <= 0) continue; // behind the camera
      final childSize = context.getChildSize(i) ?? Size.zero;
      final x = (v.x / v.w + 1) / 2 * context.size.width - childSize.width / 2;
      final y =
          (1 - v.y / v.w) / 2 * context.size.height - childSize.height / 2;
      context.paintChild(i, transform: Matrix4.translationValues(x, y, 0));
    }
  }

  Vector3? _positionOf(World world, _AnchorSlot slot) {
    final node = world.tryGet<SceneNode>(slot.entity);
    if (node != null) {
      final storage = node.node.globalTransform.storage;
      return Vector3(storage[12], storage[13], storage[14]);
    }
    return world.tryGet<SceneTransform>(slot.entity)?.translation;
  }

  @override
  bool shouldRepaint(_AnchorFlowDelegate oldDelegate) =>
      !identical(_slots, oldDelegate._slots) ||
      !identical(_game, oldDelegate._game);
}
