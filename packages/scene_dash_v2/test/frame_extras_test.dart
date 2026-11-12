import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/physics.dart' show BasicSimulation, PhysicsWorld;
import 'package:flutter_scene/scene.dart' show Node, Scene;
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2/scene_dash_v2.dart';
import 'package:scene_dash_v2/src/scene_driver.dart' show PhysicsStepMirror;

enum Act { left, fire }

const _frame = Duration(milliseconds: 16);

void _drift(World world) {
  world.query<SceneTransform>().having<Drifting>().each((_, t) => t.x += 1);
}

final class Drifting {
  const Drifting();
}

void main() {
  test('onTick clamps the wall delta before the clock scales it', () async {
    final game = await WorldGame.boot();
    game.clock.timeScale = 0.5;
    game.onTick(_frame, 5);
    expect(game.world.unscaledDelta, 0.25);
    expect(game.world.delta, 0.125);
    game.onTick(_frame, -1);
    expect(game.world.unscaledDelta, 0);
    await game.shutdown();

    final loose = await WorldGame.boot(maxFrameDelta: 2);
    loose.onTick(_frame, 5);
    expect(loose.world.unscaledDelta, 2);
    await loose.shutdown();
  });

  group('interpolated sync', () {
    late WorldGame game;
    late Node node;
    late Entity entity;
    late SceneTransform transform;
    late InterpolateTransform interpolation;

    setUp(() async {
      node = Node();
      transform = SceneTransform(0, 0, 0);
      interpolation = InterpolateTransform();
      game = await WorldGame.boot(
        features: [
          (game) {
            game.addSystem(Schedules.fixedUpdate, _drift);
            entity = game.world.spawn([
              transform,
              NodeRef(node),
              interpolation,
              const Drifting(),
            ]);
          },
        ],
      );
    });

    tearDown(() => game.shutdown());

    test('writes the blend to the node and leaves the component alone', () {
      game.onTick(_frame, 1.5 / 60);
      expect(game.world.fixedTime.alpha, closeTo(0.5, 1e-6));
      expect(transform.x, 1);
      expect(node.localTransform.getTranslation().x, closeTo(0.5, 1e-6));
    });

    test('snap writes the current transform without blending', () {
      game.onTick(_frame, 1.5 / 60);
      game.world.get<InterpolateTransform>(entity).snap();
      game.onTick(_frame, 0.001);
      expect(node.localTransform.getTranslation().x, 1);
    });
  });

  test('alpha mirrors the scene physics accumulator', () {
    final physics = PhysicsWorld(BasicSimulation());
    final mirror = PhysicsStepMirror();
    final fixed = physics.fixedTimestep;
    var accumulator = 0.0;
    for (final frame in [1.5, 0.25, 1.0, 2.25, 0.5, 12.0, 0.75, 3.0]) {
      final dt = frame * fixed;
      var steps = 0;
      accumulator = Scene.advancePhysics(
        world: physics,
        fixedUpdateWalk: (_) => steps++,
        accumulator: accumulator,
        frameDt: dt,
      );
      final alpha = mirror.advance(
        frameDt: dt,
        steps: steps,
        fixedTimestep: fixed,
        maxSubsteps: physics.maxSubsteps,
      );
      expect(alpha, closeTo(accumulator / fixed, 1e-9), reason: 'frame $frame');
    }
  });

  test('Static props sync once and again only on re-insert', () async {
    final node = Node();
    late Entity prop;
    final transform = SceneTransform(1, 0, 0);
    final game = await WorldGame.boot(
      features: [
        (game) =>
            prop = game.world.spawn([transform, NodeRef(node), const Static()]),
      ],
    );
    game.onTick(_frame, 1 / 60);
    expect(node.localTransform.getTranslation().x, 1);
    transform.x = 5;
    game.onTick(_frame, 1 / 60);
    expect(node.localTransform.getTranslation().x, 1);
    game.world.spawn([SceneTransform(3, 0, 0), NodeRef(Node())]);
    game.onTick(_frame, 1 / 60);
    game.onTick(_frame, 1 / 60);
    expect(node.localTransform.getTranslation().x, 1);
    game.world.add(prop, SceneTransform(7, 0, 0));
    game.onTick(_frame, 1 / 60);
    game.onTick(_frame, 1 / 60);
    expect(node.localTransform.getTranslation().x, 7);
    await game.shutdown();
  });

  test('reassemble reports the restart rule once', () async {
    final messages = <String>[];
    final game = await WorldGame.boot(onDiagnostic: messages.add);
    game
      ..reassemble()
      ..reassemble();
    expect(messages.where((m) => m.contains('hot restart')), hasLength(1));
    await game.shutdown();
  });

  group('InputBindings', () {
    late ButtonInput<Act> input;

    Widget bindings({Widget? child}) => Directionality(
      textDirection: TextDirection.ltr,
      child: InputBindings<Act>(
        input: input,
        keys: {
          LogicalKeyboardKey.keyA: Act.left,
          LogicalKeyboardKey.arrowLeft: Act.left,
          LogicalKeyboardKey.space: Act.fire,
        },
        child:
            child ??
            const Center(
              child: TouchAction<Act>(
                action: Act.fire,
                child: SizedBox(width: 100, height: 100),
              ),
            ),
      ),
    );

    setUp(() => input = ButtonInput<Act>());

    testWidgets('two keys on one action release only when both lift', (
      tester,
    ) async {
      await tester.pumpWidget(bindings());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      expect(input.pressed(Act.left), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      expect(input.pressed(Act.left), isFalse);
    });

    testWidgets('a key held across a remap releases what it pressed', (
      tester,
    ) async {
      await tester.pumpWidget(bindings());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: InputBindings<Act>(
            input: input,
            keys: {LogicalKeyboardKey.keyA: Act.fire},
            child: const SizedBox(),
          ),
        ),
      );
      expect(input.pressed(Act.left), isFalse);
      expect(input.pressed(Act.fire), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      expect(input.anyPressed, isFalse);
    });

    testWidgets('touch and key share an action', (tester) async {
      await tester.pumpWidget(bindings());
      final touch = await tester.startGesture(
        tester.getCenter(find.byType(SizedBox)),
      );
      expect(input.pressed(Act.fire), isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await touch.up();
      expect(input.pressed(Act.fire), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(input.pressed(Act.fire), isFalse);
    });

    testWidgets('losing focus releases held keys', (tester) async {
      await tester.pumpWidget(bindings());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      expect(input.pressed(Act.left), isTrue);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(input.pressed(Act.left), isFalse);
    });

    testWidgets('pausing the app releases everything', (tester) async {
      await tester.pumpWidget(bindings());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.startGesture(tester.getCenter(find.byType(SizedBox)));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(input.anyPressed, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('warns when the input is not the world resource', (
      tester,
    ) async {
      final messages = <String>[];
      final game = await WorldGame.boot(onDiagnostic: messages.add);
      Widget host(ButtonInput<Act>? input) => GameScope(
        game: game,
        child: InputBindings<Act>(
          input: input,
          keys: {LogicalKeyboardKey.keyA: Act.left},
          child: const SizedBox(),
        ),
      );
      await tester.pumpWidget(host(null));
      expect(messages.where((m) => m.contains('InputBindings')), isEmpty);
      await tester.pumpWidget(host(input));
      expect(messages.where((m) => m.contains('InputBindings')), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await game.shutdown();
    });

    testWidgets('disposing releases everything', (tester) async {
      await tester.pumpWidget(bindings());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.pumpWidget(const SizedBox());
      expect(input.anyPressed, isFalse);
    });
  });
}
