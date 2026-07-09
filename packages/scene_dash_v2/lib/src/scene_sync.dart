import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:vector_math/vector_math.dart' show Matrix4;

import 'scene_node.dart';

/// Extracts a node-local translation `(x, y, z)` from a game transform
/// component of type [T].
typedef NodeTranslation<T> = (double x, double y, double z) Function(
    T transform);

/// Writes a game transform component [source] into [target], the bound node's
/// mutable local transform matrix.
typedef NodeTransformWriter<T> = void Function(T source, Matrix4 target);

/// Hand-written system adapter that writes each entity's transform onto its
/// bound [SceneNode] node.
///
/// Each entity's candidate matrix is composed into a reused scratch (no
/// per-entity `Matrix4` allocation) and written onto the node — with
/// [Node.markTransformDirty] so `flutter_scene` recomputes world transforms —
/// **only when it differs** from the node's current matrix. Entities that did
/// not move therefore never invalidate the scene's transform and bounds
/// caches. Entities tagged [PhysicsDriven] are excluded — their node transform
/// is authored elsewhere (the `PhysicsWorld`'s own fixed-step interpolation for
/// dynamic bodies, or a kinematic character controller), so writing it here
/// would fight that authority and stutter the interpolated pose.
final class SyncSceneNodesAdapter<T extends Object>
    implements SystemAdapter, SystemAccessProvider {
  /// Mutating the bound node's transform counts as writing [SceneNode],
  /// matching how generated systems declare node mutation through the ref.
  @override
  SystemAccess get access =>
      SystemAccess(reads: <Type>{T}, writes: const <Type>{SceneNode});

  final NodeTransformWriter<T> _writeTransform;
  late final Query2<T, SceneNode> _query;

  /// Reused candidate matrix, seeded from the node's current matrix each
  /// entity so a partial writer (translation-only) keeps the cells it does
  /// not own.
  final Matrix4 _scratch = Matrix4.zero();

  /// Number of nodes actually written (not skipped) by the last [run].
  @visibleForTesting
  int lastRunWrites = 0;

  SyncSceneNodesAdapter(NodeTranslation<T> translationOf)
      : _writeTransform = _writerFromTranslation(translationOf);

  SyncSceneNodesAdapter.full(this._writeTransform);

  @override
  void initialize(World world) {
    world
      ..ensureObjectStore<T>()
      ..ensureObjectStore<SceneNode>()
      ..ensureTagStore<PhysicsDriven>();
    _query = world.query2<T, SceneNode>(
      withoutTypes: const [PhysicsDriven],
    );
  }

  @override
  void run() {
    lastRunWrites = 0;
    _query.each((entity, transform, binding) {
      final target = binding.node.localTransform;
      _scratch.setFrom(target);
      _writeTransform(transform, _scratch);
      if (_storageEquals(_scratch, target)) return;
      target.setFrom(_scratch);
      binding.node.markTransformDirty();
      lastRunWrites++;
    });
  }

  static bool _storageEquals(Matrix4 a, Matrix4 b) {
    final sa = a.storage;
    final sb = b.storage;
    for (var i = 0; i < 16; i++) {
      if (sa[i] != sb[i]) return false;
    }
    return true;
  }

  static NodeTransformWriter<T> _writerFromTranslation<T>(
    NodeTranslation<T> translationOf,
  ) {
    return (source, target) {
      final (x, y, z) = translationOf(source);
      target.setTranslationRaw(x, y, z);
    };
  }
}

/// Synchronizes a game's own transform component [T] onto bound nodes, for
/// games that do not use the integration's standard `SceneTransform` (which `Game`
/// syncs automatically):
///
/// ```dart
/// game.addPlugin(CustomSceneSyncPlugin<MyTransform>(
///   translationOf: (t) => (t.x, t.y, t.z),
/// ));
///
/// game.addPlugin(CustomSceneSyncPlugin<MyFullTransform>(
///   writeTransform: (source, target) {
///     target.setFromTranslationRotationScale(
///       source.translation,
///       source.rotation,
///       source.scale,
///     );
///   },
/// ));
/// ```
final class CustomSceneSyncPlugin<T extends Object> extends Plugin {
  final NodeTranslation<T>? translationOf;
  final NodeTransformWriter<T>? writeTransform;
  final SystemLabel label;

  CustomSceneSyncPlugin({
    this.translationOf,
    this.writeTransform,
    this.label = const SystemLabel('scene.syncCustomTransform'),
  }) {
    if ((translationOf == null) == (writeTransform == null)) {
      throw ArgumentError(
        'Provide exactly one of translationOf or writeTransform.',
      );
    }
  }

  @override
  void build(AppBuilder app) {
    final writer = writeTransform;
    app.addSystemAdapter(
      writer == null
          ? SyncSceneNodesAdapter<T>(translationOf!)
          : SyncSceneNodesAdapter<T>.full(writer),
      schedule: Schedules.renderSync,
      label: label,
    );
  }
}
