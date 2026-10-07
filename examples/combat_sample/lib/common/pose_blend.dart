import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

final class PoseBlend {
  static final Expando<PoseBlend> _attached = Expando();
  static final Expando<bool> _hooked = Expando();

  factory PoseBlend.of(Node model) =>
      (_attached[model] ??= PoseBlend._(model)).._hookMeshes(model);

  PoseBlend._(Node model) {
    final joints = <Node>{};
    void visit(Node node) {
      final skin = node.skin;
      if (skin != null) joints.addAll(skin.joints.whereType<Node>());
      node.children.forEach(visit);
    }

    visit(model);
    _joints = joints.toList(growable: false);
    _from = [for (final _ in _joints) _Pose()];
    model.addComponent(_FrameStart(this));
  }

  void _hookMeshes(Node node) {
    if (node.mesh != null && _hooked[node] == null) {
      _hooked[node] = true;
      node.addComponent(_BeforeSkinning(this));
    }
    for (final child in node.children) {
      _hookMeshes(child);
    }
  }

  late final List<Node> _joints;
  late final List<_Pose> _from;
  final _Pose _current = _Pose();
  double _seconds = 0;
  double _elapsed = 0;
  bool _pending = false;

  void start(double seconds) {
    if (seconds <= 0) return;
    for (var i = 0; i < _joints.length; i++) {
      _from[i].capture(_joints[i].localTransform);
    }
    _seconds = seconds;
    _elapsed = 0;
  }

  bool get _blending => _elapsed < _seconds;

  void _beginFrame(double dt) {
    if (!_blending) return;
    _elapsed += dt;
    _pending = true;
  }

  void _apply() {
    if (!_pending) return;
    _pending = false;
    final t = (_elapsed / _seconds).clamp(0.0, 1.0);
    final toTarget = t * t * (3 - 2 * t);
    for (final (i, joint) in _joints.indexed) {
      _current.capture(joint.localTransform);
      _from[i].blendInto(_current, toTarget);
      joint.mutateLocalTransform(_current.write);
    }
  }
}

final class _Pose {
  final Vector3 translation = Vector3.zero();
  final Quaternion rotation = Quaternion.identity();
  final Vector3 scale = Vector3.all(1);

  void capture(Matrix4 matrix) =>
      matrix.decompose(translation, rotation, scale);

  void write(Matrix4 matrix) =>
      matrix.setFromTranslationRotationScale(translation, rotation, scale);

  void blendInto(_Pose target, double toTarget) {
    Vector3.mix(translation, target.translation, toTarget, target.translation);
    Vector3.mix(scale, target.scale, toTarget, target.scale);
    final to = target.rotation;
    final sign = rotation.dot(to) < 0 ? -1.0 : 1.0;
    to.setValues(
      rotation.x + (to.x * sign - rotation.x) * toTarget,
      rotation.y + (to.y * sign - rotation.y) * toTarget,
      rotation.z + (to.z * sign - rotation.z) * toTarget,
      rotation.w + (to.w * sign - rotation.w) * toTarget,
    );
    to.normalize();
  }
}

final class _FrameStart extends Component {
  _FrameStart(this._blend);

  final PoseBlend _blend;

  @override
  void update(double deltaSeconds) => _blend._beginFrame(deltaSeconds);
}

final class _BeforeSkinning extends Component {
  _BeforeSkinning(this._blend);

  final PoseBlend _blend;

  @override
  void update(double deltaSeconds) => _blend._apply();
}
