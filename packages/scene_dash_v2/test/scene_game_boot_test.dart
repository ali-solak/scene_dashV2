import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:flutter_scene/physics.dart';

enum RunMode { title, playing }

final class Score {
  int value = 0;
}

final class Rock {
  Rock(this.size);
  final double size;
}

void main() {
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
    // Headless games still have the debug-draw buffer.
    game.world.debugDraw.enabled = false;
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
