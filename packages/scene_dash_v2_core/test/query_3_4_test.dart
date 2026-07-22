import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

final class A {
  final int v;
  A(this.v);
}

final class B {
  final int v;
  B(this.v);
}

final class C {
  final int v;
  C(this.v);
}

final class D {
  final int v;
  D(this.v);
}

final class Tagged {
  const Tagged();
}

World _world() {
  return World()
    ..stores.register<A>(ObjectComponentStore<A>())
    ..stores.register<B>(ObjectComponentStore<B>())
    ..stores.register<C>(ObjectComponentStore<C>())
    ..stores.register<D>(ObjectComponentStore<D>())
    ..stores.register<Tagged>(TagStore());
}

Entity _spawn(
  World world, {
  int? a,
  int? b,
  int? c,
  int? d,
  bool tagged = false,
}) {
  final e = world.entities.spawn();
  if (a != null) world.insertNow<A>(e, A(a));
  if (b != null) world.insertNow<B>(e, B(b));
  if (c != null) world.insertNow<C>(e, C(c));
  if (d != null) world.insertNow<D>(e, D(d));
  if (tagged) world.insertNow<Tagged>(e, const Tagged());
  return e;
}

void main() {
  group('Query3', () {
    test('matches only entities with all three components', () {
      final world = _world();
      final all = _spawn(world, a: 1, b: 2, c: 3);
      _spawn(world, a: 1, b: 2); // missing C
      _spawn(world, a: 1, c: 3); // missing B

      final matched = <Entity>[];
      world.query3<A, B, C>().each((e, a, b, c) {
        matched.add(e);
        expect(a.v + b.v + c.v, 6);
      });
      expect(matched, <Entity>[all]);
    });

    test('honours requires/excludes filters', () {
      final world = _world();
      final ok = _spawn(world, a: 1, b: 1, c: 1, tagged: true);
      _spawn(world, a: 1, b: 1, c: 1); // not tagged → excluded by requires

      final matched = <Entity>[];
      world
          .query3<A, B, C>(withTypes: const [Tagged])
          .each((e, a, b, c) => matched.add(e));
      expect(matched, <Entity>[ok]);
    });
  });

  group('Query4', () {
    test('matches only entities with all four components', () {
      final world = _world();
      final all = _spawn(world, a: 1, b: 2, c: 3, d: 4);
      _spawn(world, a: 1, b: 2, c: 3); // missing D

      final sums = <int>[];
      world.query4<A, B, C, D>().each((e, a, b, c, d) {
        sums.add(a.v + b.v + c.v + d.v);
      });
      expect(sums, <int>[10]);
      expect(all.isValid, isTrue);
    });

    test('excludes filter removes matches', () {
      final world = _world();
      _spawn(world, a: 1, b: 1, c: 1, d: 1, tagged: true);
      final kept = _spawn(world, a: 1, b: 1, c: 1, d: 1);

      final matched = <Entity>[];
      world
          .query4<A, B, C, D>(withoutTypes: const [Tagged])
          .each((e, a, b, c, d) => matched.add(e));
      expect(matched, <Entity>[kept]);
    });
  });

  group('eachUntil / firstWhere / any', () {
    test('Query3.eachUntil stops when the callback returns false', () {
      final world = _world();
      for (var i = 0; i < 4; i++) {
        _spawn(world, a: i, b: i, c: i);
      }

      var visits = 0;
      world.query3<A, B, C>().eachUntil((e, a, b, c) {
        visits++;
        return visits < 2;
      });
      expect(visits, 2);
    });

    test('Query3.eachUntil matches when a later store drives', () {
      final world = _world();
      // Many A rows, one C row: the C store must drive.
      for (var i = 0; i < 30; i++) {
        _spawn(world, a: i);
      }
      final all = _spawn(world, a: 1, b: 2, c: 3);

      final seen = <Entity>[];
      world.query3<A, B, C>().eachUntil((e, a, b, c) {
        seen.add(e);
        return true;
      });
      expect(seen, <Entity>[all]);
    });

    test('Query3.firstWhere returns the matching record or null', () {
      final world = _world();
      _spawn(world, a: 1, b: 1, c: 1);
      final wanted = _spawn(world, a: 7, b: 8, c: 9);

      final match = world.query3<A, B, C>().firstWhere(
        (e, a, b, c) => a.v == 7,
      );
      expect(match, isNotNull);
      final (entity, a, b, c) = match!;
      expect(entity, wanted);
      expect(b.v, 8);
      expect(c.v, 9);

      expect(
        world.query3<A, B, C>().firstWhere((e, a, b, c) => a.v == 99),
        isNull,
      );
    });

    test('Query4.eachUntil counts callback invocations exactly', () {
      final world = _world();
      for (var i = 0; i < 4; i++) {
        _spawn(world, a: i, b: i, c: i, d: i);
      }

      var visits = 0;
      world.query4<A, B, C, D>().eachUntil((e, a, b, c, d) {
        visits++;
        return visits < 3;
      });
      expect(visits, 3);
    });

    test('Query4.eachUntil rejects structural mutation in the callback', () {
      final world = _world();
      _spawn(world, a: 1, b: 1, c: 1, d: 1);
      final extra = world.entities.spawn();

      expect(
        () => world.query4<A, B, C, D>().eachUntil((e, a, b, c, d) {
          world.insertNow<A>(extra, A(9));
          return true;
        }),
        throwsA(isA<AssertionError>()),
      );
    });

    test('Query4.firstWhere respects excludes filters', () {
      final world = _world();
      _spawn(world, a: 1, b: 1, c: 1, d: 1, tagged: true);
      final kept = _spawn(world, a: 2, b: 2, c: 2, d: 2);

      final match = world
          .query4<A, B, C, D>(withoutTypes: const [Tagged])
          .firstWhere((e, a, b, c, d) => true);
      expect(match!.$1, kept);
    });

    test('Query4.any stops at the first hit and honours empty queries', () {
      final world = _world();
      expect(world.query4<A, B, C, D>().any((e, a, b, c, d) => true), isFalse);

      for (var i = 0; i < 3; i++) {
        _spawn(world, a: i, b: i, c: i, d: i);
      }
      var visits = 0;
      final found = world.query4<A, B, C, D>().any((e, a, b, c, d) {
        visits++;
        return true;
      });
      expect(found, isTrue);
      expect(visits, 1);
    });
  });

  group('components (record accessor)', () {
    test('Query3.components returns all three components or null', () {
      final world = _world();
      final all = _spawn(world, a: 1, b: 2, c: 3);
      final missing = _spawn(world, a: 1, b: 2); // no C

      final query = world.query3<A, B, C>();
      final record = query.components(all);
      expect(record, isNotNull);
      final (a, b, c) = record!;
      expect(a.v + b.v + c.v, 6);

      expect(query.components(missing), isNull);
    });

    test('Query4.components honours filters and staleness', () {
      final world = _world();
      final tagged = _spawn(world, a: 1, b: 1, c: 1, d: 1, tagged: true);
      final all = _spawn(world, a: 1, b: 2, c: 3, d: 4);

      final untagged = world.query4<A, B, C, D>(withoutTypes: const [Tagged]);
      expect(untagged.components(tagged), isNull);

      final record = untagged.components(all);
      expect(record, isNotNull);
      expect(record!.$4.v, 4);

      world.despawnNow(all);
      expect(untagged.components(all), isNull, reason: 'stale handle');
    });
  });

  group('get (random access)', () {
    test('Query3.get calls back with all three components when matched', () {
      final world = _world();
      final all = _spawn(world, a: 1, b: 2, c: 3);
      final missing = _spawn(world, a: 1, b: 2); // no C

      var sum = 0;
      final matched = world.query3<A, B, C>().get(all, (e, a, b, c) {
        expect(e, all);
        sum = a.v + b.v + c.v;
      });
      expect(matched, isTrue);
      expect(sum, 6);
      expect(world.query3<A, B, C>().get(missing, (e, a, b, c) {}), isFalse);
    });

    test('Query3.get honours filters', () {
      final world = _world();
      final tagged = _spawn(world, a: 1, b: 1, c: 1, tagged: true);
      final plain = _spawn(world, a: 1, b: 1, c: 1);

      final q = world.query3<A, B, C>(withTypes: const [Tagged]);
      expect(q.get(tagged, (e, a, b, c) {}), isTrue);
      expect(q.get(plain, (e, a, b, c) {}), isFalse);
    });

    test('Query4.get calls back with all four components when matched', () {
      final world = _world();
      final all = _spawn(world, a: 1, b: 2, c: 3, d: 4);
      final missing = _spawn(world, a: 1, b: 2, c: 3); // no D

      var sum = 0;
      final matched = world.query4<A, B, C, D>().get(
        all,
        (e, a, b, c, d) => sum = a.v + b.v + c.v + d.v,
      );
      expect(matched, isTrue);
      expect(sum, 10);
      expect(
        world.query4<A, B, C, D>().get(missing, (e, a, b, c, d) {}),
        isFalse,
      );
    });

    test('Query4.get returns false for a stale entity handle', () {
      final world = _world();
      final e = _spawn(world, a: 1, b: 1, c: 1, d: 1);
      world.despawnNow(e);
      expect(world.query4<A, B, C, D>().get(e, (en, a, b, c, d) {}), isFalse);
    });
  });
}
