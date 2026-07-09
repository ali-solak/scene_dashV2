import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2_core/advanced.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:vector_math/vector_math.dart' show Matrix4, Quaternion, Vector3;

final class TestTransform {
  double x;
  double y;
  double z;
  TestTransform(this.x, this.y, this.z);
}

final class TestFullTransform {
  final Vector3 translation;
  final Quaternion rotation;
  final Vector3 scale;

  TestFullTransform({
    required this.translation,
    required this.rotation,
    required this.scale,
  });
}

void _expectMatrixClose(Matrix4 actual, Matrix4 expected) {
  for (var i = 0; i < 16; i++) {
    expect(actual[i], closeTo(expected[i], 1e-9), reason: 'matrix[$i]');
  }
}

void main() {
  test('SceneTransform preserves x/y/z compatibility over translation', () {
    final transform = SceneTransform(1, 2, 3)
      ..x = 4
      ..y = 5
      ..z = 6
      ..setScale(2, 3, 4)
      ..setUniformScale(2)
      ..setRotationIdentity();

    expect(transform.translation.x, 4);
    expect(transform.translation.y, 5);
    expect(transform.translation.z, 6);
    expect(transform.scale, Vector3.all(2));
    expect(transform.rotation, Quaternion.identity());
  });

  test('writes transform onto the bound node, skipping PhysicsDriven', () {
    final world = World()
      ..stores.register<TestTransform>(ObjectComponentStore<TestTransform>())
      ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>())
      ..stores.register<PhysicsDriven>(TagStore());

    final syncedNode = Node();
    final synced = world.entities.spawn();
    world
      ..insertNow<TestTransform>(synced, TestTransform(1, 2, 3))
      ..insertNow<SceneNode>(synced, SceneNode(syncedNode));

    final physicsNode = Node();
    final physics = world.entities.spawn();
    world
      ..insertNow<TestTransform>(physics, TestTransform(9, 9, 9))
      ..insertNow<SceneNode>(physics, SceneNode(physicsNode))
      ..insertNow<PhysicsDriven>(physics, const PhysicsDriven());

    final adapter = SyncSceneNodesAdapter<TestTransform>(
      (t) => (t.x, t.y, t.z),
    )..initialize(world);
    adapter.run();

    final t = syncedNode.localTransform.getTranslation();
    expect(t.x, closeTo(1, 1e-9));
    expect(t.y, closeTo(2, 1e-9));
    expect(t.z, closeTo(3, 1e-9));

    // Physics-driven node is excluded → still identity translation.
    final p = physicsNode.localTransform.getTranslation();
    expect(p.x, 0);
    expect(p.y, 0);
    expect(p.z, 0);
  });

  test('CustomSceneSyncPlugin syncs a custom translation in renderSync', () {
    final app = App();
    app.world.stores
      ..register<TestTransform>(ObjectComponentStore<TestTransform>())
      ..register<SceneNode>(ObjectComponentStore<SceneNode>());

    final node = Node();
    final e = app.world.entities.spawn();
    app.world
      ..insertNow<TestTransform>(e, TestTransform(4, 5, 6))
      ..insertNow<SceneNode>(e, SceneNode(node));

    app.addPlugin(
      CustomSceneSyncPlugin<TestTransform>(
        translationOf: (t) => (t.x, t.y, t.z),
      ),
    );
    app.start();
    app.runSchedule(Schedules.renderSync);

    final t = node.localTransform.getTranslation();
    expect(t.x, closeTo(4, 1e-9));
    expect(t.z, closeTo(6, 1e-9));
  });

  test('CustomSceneSyncPlugin can write a full custom transform', () {
    final app = App();
    app.world.stores
      ..register<TestFullTransform>(ObjectComponentStore<TestFullTransform>())
      ..register<SceneNode>(ObjectComponentStore<SceneNode>());

    final source = TestFullTransform(
      translation: Vector3(1, 2, 3),
      rotation: Quaternion.axisAngle(Vector3(0, 1, 0), 0.5),
      scale: Vector3(2, 3, 4),
    );
    final node = Node();
    final e = app.world.entities.spawn();
    app.world
      ..insertNow<TestFullTransform>(e, source)
      ..insertNow<SceneNode>(e, SceneNode(node));

    app.addPlugin(
      CustomSceneSyncPlugin<TestFullTransform>(
        writeTransform: (transform, target) {
          target.setFromTranslationRotationScale(
            transform.translation,
            transform.rotation,
            transform.scale,
          );
        },
      ),
    );
    app.start();
    app.runSchedule(Schedules.renderSync);

    final expected = Matrix4.zero()
      ..setFromTranslationRotationScale(
        source.translation,
        source.rotation,
        source.scale,
      );
    _expectMatrixClose(node.localTransform, expected);
  });

  test('CustomSceneSyncPlugin requires exactly one sync callback', () {
    expect(
      () => CustomSceneSyncPlugin<TestTransform>(),
      throwsArgumentError,
    );
    expect(
      () => CustomSceneSyncPlugin<TestTransform>(
        translationOf: (t) => (t.x, t.y, t.z),
        writeTransform: (source, target) {},
      ),
      throwsArgumentError,
    );
  });

  test('sync skips nodes whose transform did not change', () {
    final world = World()
      ..stores.register<TestTransform>(ObjectComponentStore<TestTransform>())
      ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>());

    final movingNode = Node();
    final staticNode = Node();
    final moving = world.entities.spawn();
    final static_ = world.entities.spawn();
    final movingTransform = TestTransform(1, 2, 3);
    world
      ..insertNow<TestTransform>(moving, movingTransform)
      ..insertNow<SceneNode>(moving, SceneNode(movingNode))
      ..insertNow<TestTransform>(static_, TestTransform(4, 5, 6))
      ..insertNow<SceneNode>(static_, SceneNode(staticNode));

    final adapter = SyncSceneNodesAdapter<TestTransform>(
      (t) => (t.x, t.y, t.z),
    )..initialize(world);

    adapter.run();
    expect(adapter.lastRunWrites, 2, reason: 'first run writes both nodes');

    adapter.run();
    expect(adapter.lastRunWrites, 0, reason: 'nothing moved: nothing written');

    movingTransform.x = 10;
    adapter.run();
    expect(adapter.lastRunWrites, 1, reason: 'only the moved node is written');
    expect(
      movingNode.localTransform.getTranslation().x,
      closeTo(10, 1e-9),
    );
  });

  test('translation-only sync preserves the node\'s rotation and scale', () {
    final world = World()
      ..stores.register<TestTransform>(ObjectComponentStore<TestTransform>())
      ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>());

    final original = Matrix4.zero()
      ..setFromTranslationRotationScale(
        Vector3.zero(),
        Quaternion.axisAngle(Vector3(0, 1, 0), 0.5),
        Vector3(2, 2, 2),
      );
    final node = Node(localTransform: original.clone());
    final e = world.entities.spawn();
    world
      ..insertNow<TestTransform>(e, TestTransform(1, 2, 3))
      ..insertNow<SceneNode>(e, SceneNode(node));

    SyncSceneNodesAdapter<TestTransform>((t) => (t.x, t.y, t.z))
      ..initialize(world)
      ..run();

    final expected = original.clone()..setTranslationRaw(1, 2, 3);
    _expectMatrixClose(node.localTransform, expected);
  });

  test('standard SceneTransform sync writes full TRS onto the bound node', () {
    // This is the adapter Game installs automatically for SceneTransform.
    final world = World()
      ..stores.register<SceneTransform>(ObjectComponentStore<SceneTransform>())
      ..stores.register<SceneNode>(ObjectComponentStore<SceneNode>());

    final node = Node();
    final e = world.entities.spawn();
    final transform = SceneTransform.trs(
      translation: Vector3(7, 8, 9),
      rotation: Quaternion.axisAngle(Vector3(0, 0, 1), 0.25),
      scale: Vector3(2, 3, 4),
    );
    world
      ..insertNow<SceneTransform>(e, transform)
      ..insertNow<SceneNode>(e, SceneNode(node));

    SyncSceneNodesAdapter<SceneTransform>.full(
      (transform, target) => target.setFromTranslationRotationScale(
        transform.translation,
        transform.rotation,
        transform.scale,
      ),
    )
      ..initialize(world)
      ..run();

    final expected = Matrix4.zero()
      ..setFromTranslationRotationScale(
        transform.translation,
        transform.rotation,
        transform.scale,
      );
    _expectMatrixClose(node.localTransform, expected);
  });
}
