import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:flutter_scene/physics.dart';
import 'package:flutter_scene/scene.dart' show Node;

enum RunMode { title, playing }

final class Score {
  int value = 0;
}

final class Rock {
  Rock(this.size);
  final double size;
}

void main() {
  test('surface update spawns are mounted before render sync', () async {
    final node = Node();
    Entity? spawned;
    var mountedDuringSync = false;
    final game = await WorldGame.boot(
      features: [
        (game) => game
          ..addSystem(Schedules.update, (world) {
            spawned ??= world.spawn([NodeRef(node), SceneTransform.zero()]);
          }, writes: {NodeRef, SceneTransform})
          ..addSystem(Schedules.renderSync, (world) {
            mountedDuringSync =
                world.has<Mounted>(spawned!) &&
                node.parent != null &&
                world.resource<SceneNodeIndex>().entityOf(node) == spawned;
          }, reads: {Mounted}),
      ],
    );
    addTearDown(game.shutdown);
    game.onTick(const Duration(milliseconds: 16), 1 / 60);
    expect(mountedDuringSync, isTrue);
    expect(node.parent, same(game.engine.root));
  });

  test('owned despawns detach before the frame tick', () async {
    Entity? doomedOwner;
    final game = await WorldGame.boot(
      features: [
        (game) => game.addSystem(Schedules.update, (world) {
          final owner = doomedOwner;
          if (owner != null) world.despawn(owner);
        }, writes: {NodeRef, Mounted}),
      ],
    );
    addTearDown(game.shutdown);
    final owner = game.world.spawn([]);
    final node = Node();
    final child = game.world.spawn([NodeRef(node)], ownedBy: owner);
    game.onTick(const Duration(milliseconds: 16), 1 / 60);
    expect(node.parent, same(game.engine.root));
    var detachedAtTick = false;
    game.frameTick.addListener(() {
      detachedAtTick = !game.world.isAlive(child) && node.parent == null;
    });
    doomedOwner = owner;
    // Despawn during update, after the earlier mount boundaries have run.
    game.onTick(const Duration(milliseconds: 17), 0);
    expect(detachedAtTick, isTrue);
  });

  test('boot runs features against the builder in order; systems and '
      'spawns are live; frames drive through onTick', () async {
    final order = <String>[];
    var updates = 0;
    final game = await WorldGame.boot(
      features: [
        (game) {
          order.add('a');
          game
            ..addState(RunMode.title)
            ..addSystem(
              Schedules.update,
              (world) => updates++,
              reads: const {},
            );
          game.world.insert(Score());
        },
        (game) => order.add('b'),
      ],
    );
    expect(order, ['a', 'b']);
    game.world.spawn([Rock(1)]);
    game.onTick(const Duration(milliseconds: 16), 1 / 60);
    expect(updates, 1);
    expect(game.world.query<Rock>().single.$2.size, 1);
    expect(game.world.state<RunMode>(), RunMode.title);
    expect(game.world.resource<Score>().value, 0);
  });

  test('physics boot wires the world resource, the collision channels and '
      'the promoted world.physics getter', () async {
    final physics = PhysicsWorld(BasicSimulation());
    final game = await WorldGame.boot(physics: physics);
    expect(game.world.resource<PhysicsWorld>(), same(physics));
    expect(game.world.physics, same(physics));
    expect(game.engine.root.getComponent<PhysicsWorld>(), same(physics));
    game.world.eventChannel<EntityCollision>();
  });

  test('strictAccess is enforced through boot', () async {
    expect(
      () => WorldGame.boot(
        strictAccess: true,
        features: [(game) => game.addSystem(Schedules.update, (world) {})],
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('frameTick pulses once per frame, after the world resolved', () async {
    final game = await WorldGame.boot();
    var pulses = 0;
    game.frameTick.addListener(() => pulses++);
    game.onTick(const Duration(milliseconds: 16), 1 / 60);
    game.onTick(const Duration(milliseconds: 32), 1 / 60);
    expect(pulses, 2);
  });
}
