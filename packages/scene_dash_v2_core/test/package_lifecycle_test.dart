import 'package:scene_dash_v2_core/advanced.dart' show EventChannel;
import 'package:scene_dash_v2_core/scene_dash_v2_core.dart';
import 'package:test/test.dart';

class Tracked implements Disposable {
  Tracked(this.name, this.log, {this.failure});
  final String name;
  final List<String> log;
  final Object? failure;

  @override
  void dispose() {
    log.add(name);
    if (failure case final error?) throw error;
  }

  // Disposal must use identity, even for resources with value equality.
  @override
  bool operator ==(Object other) => other is Tracked;
  @override
  int get hashCode => 0;
}

void main() {
  test(
    'shutdown attempts each stage and preserves original failures',
    () async {
      final log = <String>[];
      final scheduleError = StateError('shutdown schedule');
      final cleanupError = StateError('async cleanup');
      final resourceError = StateError('resource');
      final game = TestGame.headless(
        features: [
          (g) => g.addSystem(Schedules.shutdown, (_) {
            log.add('schedule');
            throw scheduleError;
          }),
        ],
      );
      game.world.resources
        ..insert<Tracked>(Tracked('first resource', log))
        ..insert<Object>(
          Tracked('second resource', log, failure: resourceError),
        )
        ..insert(42)
        ..getOrInsert<String>(() => 'plain');
      game.app.addCleanup(() => log.add('first cleanup'));
      game.app.addCleanup(() async {
        await Future<void>.value();
        log.add('second cleanup');
        throw cleanupError;
      });
      game.start();
      await expectLater(
        game.shutdown(),
        throwsA(
          isA<CleanupException>()
              .having(
                (e) => e.failures.map((f) => f.error),
                'original failures',
                [scheduleError, cleanupError, resourceError],
              )
              .having(
                (e) =>
                    e.failures.every((f) => f.stackTrace.toString().isNotEmpty),
                'stack traces',
                isTrue,
              ),
        ),
      );
      expect(log, [
        'schedule',
        'second cleanup',
        'first cleanup',
        'second resource',
        'first resource',
      ]);
      expect(game.world.resources.values, isEmpty);
      await game.shutdown();
      expect(log, hasLength(5));
    },
  );

  test('disposed readers release retention and reject further reads', () {
    final channel = EventChannel<int>(retainedUpdates: null);
    final abandoned = channel.reader();
    final active = channel.reader();
    channel.send(1);
    expect(active.drain(), [1]);
    channel.update();
    expect(channel.pendingCount, 1);
    abandoned.dispose();
    abandoned.dispose();
    expect(abandoned.isDisposed, isTrue);
    expect(channel.readerCount, 1);
    channel.update();
    expect(channel.pendingCount, 0);
    expect(() => abandoned.hasUnread, throwsStateError);
    expect(abandoned.consume, throwsStateError);
    expect(abandoned.drain, throwsStateError);
    expect(() => abandoned.forEach((_) {}), throwsStateError);
    channel.send(2);
    expect(active.drain(), [2]);
    active.dispose();
    expect(channel.hasReaders, isFalse);
  });

  test('a reader can dispose itself during delivery', () {
    final channel = EventChannel<int>();
    final reader = channel.reader();
    channel
      ..send(1)
      ..send(2);
    final seen = <int>[];
    reader.forEach((event) {
      seen.add(event);
      reader.dispose();
    });
    expect(seen, [1]);
    expect(channel.readerCount, 0);
  });

  test(
    'consumeAny advances only its system cursor; shutdown releases it',
    () async {
      final consumed = <bool>[];
      final batches = <List<int>>[];
      final game = TestGame.headless(
        features: [
          (g) => g
            ..configureEvent<int>(retainedUpdates: null)
            ..addSystem(
              Schedules.update,
              (w) => consumed.add(w.consumeAny<int>()),
            )
            ..addSystem(
              Schedules.update,
              (w) => batches.add(w.events<int>().toList()),
            ),
        ],
      );
      game.pump();
      game.emit(1);
      game.emit(2);
      game.pump();
      game.pump();
      expect(consumed, [false, true, false]);
      expect(batches, [
        <int>[],
        [1, 2],
        <int>[],
      ]);
      final channel = game.world.eventChannel<int>();
      expect(channel.readerCount, 2);
      expect(() => game.world.consumeAny<int>(), throwsStateError);
      await game.shutdown();
      expect(channel.readerCount, 0);
    },
  );
}
