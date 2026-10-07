import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:vector_math/vector_math.dart' show Matrix4;

import 'node_ref.dart';
import 'scene_transform.dart';

/// Extracts a node-local translation `(x, y, z)` from a game transform
/// component of type [T].
typedef NodeTranslation<T> = (double x, double y, double z) Function(
  T transform,
);

/// Writes a game transform component [source] into [target], the bound node's
/// mutable local transform matrix.
typedef NodeTransformWriter<T> = void Function(T source, Matrix4 target);

/// Writes entity transforms to scene nodes.
///
/// Skips [PhysicsDriven] entities.
final class SyncSceneNodesAdapter<T extends Object>
    implements SystemAdapter, SystemAccessProvider {
  /// Writes [NodeRef] transforms.
  @override
  SystemAccess get access =>
      SystemAccess(reads: <Type>{T}, writes: const <Type>{NodeRef});

  final NodeTransformWriter<T> _writeTransform;
  late final Query2<T, NodeRef> _query;

  /// Reused transform matrix.
  final Matrix4 _scratch = Matrix4.zero();

  late final void Function(Matrix4 target) _copyScratch = _scratch.copyInto;

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
      ..ensureObjectStore<NodeRef>()
      ..ensureTagStore<PhysicsDriven>();
    _query = world.query2<T, NodeRef>(withoutTypes: const [PhysicsDriven]);
  }

  @override
  void run() {
    lastRunWrites = 0;
    _query.each((entity, transform, binding) {
      final target = binding.node.localTransform;
      _scratch.setFrom(target);
      _writeTransform(transform, _scratch);
      if (_storageEquals(_scratch, target)) return;
      binding.node.mutateLocalTransform(_copyScratch);
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

final class SceneTransformSyncAdapter
    implements SystemAdapter, SystemAccessProvider {
  @override
  SystemAccess get access => const SystemAccess(
    reads: <Type>{SceneTransform},
    writes: <Type>{NodeRef},
  );

  static const int _stride = 10;

  late final Query2<SceneTransform, NodeRef> _query;
  Float32List _written = Float32List(0);
  List<Matrix4?> _writtenInto = <Matrix4?>[];
  final Matrix4 _scratch = Matrix4.zero();
  late final void Function(Matrix4 target) _copyScratch = _scratch.copyInto;

  @visibleForTesting
  int lastRunWrites = 0;

  @override
  void initialize(World world) {
    world
      ..ensureObjectStore<SceneTransform>()
      ..ensureObjectStore<NodeRef>()
      ..ensureTagStore<PhysicsDriven>();
    _query = world.query2<SceneTransform, NodeRef>(
      withoutTypes: const [PhysicsDriven],
    );
  }

  @override
  void run() {
    lastRunWrites = 0;
    _query.each(_sync);
  }

  void _sync(Entity entity, SceneTransform transform, NodeRef binding) {
    final index = entity.index;
    final node = binding.node;
    final t = transform.translation.storage;
    final r = transform.rotation.storage;
    final s = transform.scale.storage;
    if (index < _writtenInto.length &&
        identical(_writtenInto[index], node.localTransform)) {
      final o = index * _stride;
      final w = _written;
      if (w[o] == t[0] &&
          w[o + 1] == t[1] &&
          w[o + 2] == t[2] &&
          w[o + 3] == r[0] &&
          w[o + 4] == r[1] &&
          w[o + 5] == r[2] &&
          w[o + 6] == r[3] &&
          w[o + 7] == s[0] &&
          w[o + 8] == s[1] &&
          w[o + 9] == s[2]) {
        return;
      }
    }
    _scratch.setFromTranslationRotationScale(
      transform.translation,
      transform.rotation,
      transform.scale,
    );
    node.mutateLocalTransform(_copyScratch);
    lastRunWrites++;
    _remember(index, node.localTransform, t, r, s);
  }

  void _remember(
    int index,
    Matrix4 matrix,
    Float32List t,
    Float32List r,
    Float32List s,
  ) {
    if (index >= _writtenInto.length) {
      var capacity = _writtenInto.isEmpty ? 64 : _writtenInto.length;
      while (capacity <= index) {
        capacity *= 2;
      }
      _writtenInto = List<Matrix4?>.filled(capacity, null)
        ..setRange(0, _writtenInto.length, _writtenInto);
      _written = Float32List(capacity * _stride)
        ..setRange(0, _written.length, _written);
    }
    _writtenInto[index] = matrix;
    final o = index * _stride;
    _written
      ..[o] = t[0]
      ..[o + 1] = t[1]
      ..[o + 2] = t[2]
      ..[o + 3] = r[0]
      ..[o + 4] = r[1]
      ..[o + 5] = r[2]
      ..[o + 6] = r[3]
      ..[o + 7] = s[0]
      ..[o + 8] = s[1]
      ..[o + 9] = s[2];
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
