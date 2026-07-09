import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

void main() {
  group('DespawnAfter', () {
    late App app;
    late FrameTime time;

    setUp(() {
      time = FrameTime();
      app = App()..insertResource<FrameTime>(time);
      app.start();
    });

    Entity spawnWithLifetime(double seconds) {
      final entity = app.world.entities.spawn();
      app.world.insertNow<DespawnAfter>(entity, DespawnAfter(seconds));
      return entity;
    }

    void tick(double delta) {
      time.delta = delta;
      app.runSchedule(Schedules.update);
    }

    test('despawns once the accumulated ticks cross the lifetime', () {
      final entity = spawnWithLifetime(0.25);

      tick(0.1);
      expect(app.world.isAlive(entity), isTrue);
      tick(0.1);
      expect(app.world.isAlive(entity), isTrue);
      tick(0.1); // 0.3s accumulated > 0.25s lifetime
      expect(app.world.isAlive(entity), isFalse);
    });

    test('entities with different lifetimes expire independently', () {
      final short = spawnWithLifetime(0.1);
      final long = spawnWithLifetime(0.5);

      tick(0.15);
      expect(app.world.isAlive(short), isFalse);
      expect(app.world.isAlive(long), isTrue);

      tick(0.4);
      expect(app.world.isAlive(long), isFalse);
    });

    test('removing the component early cancels the despawn', () {
      final entity = spawnWithLifetime(0.2);

      tick(0.1);
      app.world.removeNow<DespawnAfter>(entity);
      tick(0.5);
      tick(0.5);
      expect(app.world.isAlive(entity), isTrue);
    });

    test('game time drives the countdown: a zero delta does not advance it',
        () {
      final entity = spawnWithLifetime(0.1);

      tick(0); // paused / hitstop frame
      tick(0);
      expect(app.world.isAlive(entity), isTrue);
      tick(0.2);
      expect(app.world.isAlive(entity), isFalse);
    });

    test('throws when DespawnAfter is used without a FrameTime resource', () {
      final bare = App()..start();
      final entity = bare.world.entities.spawn();
      bare.world.insertNow<DespawnAfter>(entity, DespawnAfter(1));
      expect(
        () => bare.runSchedule(Schedules.update),
        throwsStateError,
        reason: 'a silent freeze would be a worse failure mode',
      );
    });

    test('the built-in system is inert while no entity carries the component',
        () {
      final bare = App()..start();
      // No FrameTime resource either: the empty-store early return must win.
      expect(
        () => bare.runSchedule(Schedules.update),
        returnsNormally,
      );
    });
  });
}
