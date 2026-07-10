import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

/// Coverage for [Disposable] at the framework's three call sites — game
/// shutdown, `World.reset(keepResources: false)`, and resource
/// removal/replacement — plus the ordering and double-dispose guarantees.
class _Tracked implements Disposable {
  _Tracked(this.name, this.log);
  final String name;
  final List<String> log;
  @override
  void dispose() => log.add(name);
}

final class _A extends _Tracked {
  _A(List<String> log) : super('A', log);
}

final class _B extends _Tracked {
  _B(List<String> log) : super('B', log);
}

final class _C extends _Tracked {
  _C(List<String> log) : super('C', log);
}

final class _Plain {}

void main() {
  group('game shutdown', () {
    test('disposes Disposable resources in reverse insertion order, '
        'skipping plain ones', () async {
      final log = <String>[];
      final game = TestGame.headless();
      game.world.resources
        ..insert(_A(log))
        ..insert(_Plain())
        ..insert(_B(log))
        ..insert(_C(log));
      game.start();
      await game.app.shutdown();
      expect(log, ['C', 'B', 'A'],
          reason: 'dependents (inserted later) die before dependencies');
    });
  });

  group('World.reset', () {
    test('keepResources (the default) leaves resources untouched', () {
      final log = <String>[];
      final world = World()..resources.insert(_A(log));
      world.reset();
      expect(log, isEmpty);
      expect(world.resources.tryGet<_A>(), isNotNull,
          reason: 'survivors stay registered and undisposed');
    });

    test('keepResources: false disposes the dropped resources in reverse '
        'insertion order', () {
      final log = <String>[];
      final world = World()
        ..resources.insert(_A(log))
        ..resources.insert(_B(log));
      world.reset(keepResources: false);
      expect(log, ['B', 'A']);
      expect(world.resources.tryGet<_A>(), isNull);
    });
  });

  group('removal and replacement', () {
    test('replacement disposes the outgoing instance only', () {
      final log = <String>[];
      final resources = Resources();
      final second = _Tracked('second', log);
      resources.insert(_Tracked('first', log));
      resources.insert(second);
      expect(log, ['first'], reason: 'the incoming instance stays live');
      expect(identical(resources.get<_Tracked>(), second), isTrue);
      resources.disposeAll();
      expect(log, ['first', 'second']);
    });

    test('re-inserting the identical instance disposes nothing', () {
      final log = <String>[];
      final resources = Resources();
      final a = _Tracked('a', log);
      resources
        ..insert(a)
        ..insert(a);
      expect(log, isEmpty);
    });

    test('removal disposes the outgoing instance and still returns it', () {
      final log = <String>[];
      final resources = Resources();
      final a = _Tracked('a', log);
      resources.insert(a);
      final removed = resources.remove<_Tracked>();
      expect(identical(removed, a), isTrue);
      expect(log, ['a']);
    });
  });

  group('double-dispose guard', () {
    test('the same instance under two type keys is disposed once', () {
      final log = <String>[];
      final resources = Resources();
      final a = _Tracked('a', log);
      resources.insert<_Tracked>(a);
      resources.insert<Object>(a);
      resources.disposeAll();
      expect(log, ['a']);
    });

    test('a removed instance is not disposed again by disposeAll', () {
      final log = <String>[];
      final resources = Resources();
      resources.insert(_Tracked('a', log));
      resources.remove<_Tracked>();
      resources.disposeAll();
      expect(log, ['a']);
    });

    test('re-insertion after a framework dispose marks the instance live '
        'again, so its next drop disposes it', () {
      final log = <String>[];
      final resources = Resources();
      final a = _Tracked('a', log);
      resources.insert(a);
      resources.remove<_Tracked>();
      resources.insert(a);
      resources.disposeAll();
      expect(log, ['a', 'a']);
    });
  });
}
