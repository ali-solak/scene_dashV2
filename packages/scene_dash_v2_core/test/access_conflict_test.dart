import 'package:scene_dash_v2_core/advanced.dart';
import 'package:test/test.dart';

// Marker component types used only as access keys.
final class A {}

final class B {}

/// A hand-written adapter that declares [access] and does nothing else.
final class AccessAdapter implements SystemAdapter, SystemAccessProvider {
  @override
  final SystemAccess access;

  AccessAdapter({Set<Type> reads = const {}, Set<Type> writes = const {}})
      : access = SystemAccess(reads: reads, writes: writes);

  @override
  void initialize(World world) {}

  @override
  void run() {}
}

App _app({AccessConflictPolicy policy = AccessConflictPolicy.warn}) =>
    App(accessConflictPolicy: policy);

void _add(
  App app,
  String label,
  AccessAdapter adapter, {
  ScheduleLabel schedule = Schedules.update,
  List<SystemLabel> after = const [],
}) {
  app.addSystemAdapter(
    adapter,
    schedule: schedule,
    label: SystemLabel(label),
    after: after,
  );
}

void main() {
  group('access-conflict diagnostics', () {
    test('reports a write/write conflict between unordered systems', () {
      final app = _app();
      _add(app, 'x', AccessAdapter(writes: {A}));
      _add(app, 'y', AccessAdapter(writes: {A}));
      app.start();

      expect(app.accessConflicts, hasLength(1));
      final c = app.accessConflicts.single;
      expect(c.kind, ConflictKind.writeWrite);
      expect(c.component, A);
      expect({c.a.id, c.b.id}, {'x', 'y'});
    });

    test('reports a read/write conflict', () {
      final app = _app();
      _add(app, 'writer', AccessAdapter(writes: {A}));
      _add(app, 'reader', AccessAdapter(reads: {A}));
      app.start();

      expect(app.accessConflicts, hasLength(1));
      expect(app.accessConflicts.single.kind, ConflictKind.readWrite);
    });

    test('no conflict when systems are ordered', () {
      final app = _app();
      _add(app, 'x', AccessAdapter(writes: {A}));
      _add(app, 'y', AccessAdapter(writes: {A}),
          after: const [SystemLabel('x')]);
      app.start();

      expect(app.accessConflicts, isEmpty);
    });

    test('no conflict for read/read', () {
      final app = _app();
      _add(app, 'x', AccessAdapter(reads: {A}));
      _add(app, 'y', AccessAdapter(reads: {A}));
      app.start();

      expect(app.accessConflicts, isEmpty);
    });

    test('no conflict on different components', () {
      final app = _app();
      _add(app, 'x', AccessAdapter(writes: {A}));
      _add(app, 'y', AccessAdapter(writes: {B}));
      app.start();

      expect(app.accessConflicts, isEmpty);
    });

    test('conflicts are per-schedule', () {
      final app = _app();
      _add(app, 'x', AccessAdapter(writes: {A}), schedule: Schedules.update);
      _add(app, 'y', AccessAdapter(writes: {A}),
          schedule: Schedules.fixedPrePhysics);
      app.start();

      expect(app.accessConflicts, isEmpty);
    });

    test('error policy throws on conflict', () {
      final app = _app(policy: AccessConflictPolicy.error);
      _add(app, 'x', AccessAdapter(writes: {A}));
      _add(app, 'y', AccessAdapter(writes: {A}));
      expect(app.start, throwsStateError);
    });

    test('ignore policy skips detection', () {
      final app = _app(policy: AccessConflictPolicy.ignore);
      _add(app, 'x', AccessAdapter(writes: {A}));
      _add(app, 'y', AccessAdapter(writes: {A}));
      app.start();

      expect(app.accessConflicts, isEmpty);
    });

    test('warn policy routes messages to onDiagnostic', () {
      final messages = <String>[];
      final app = App(onDiagnostic: messages.add)
        ..addSystemAdapter(
          AccessAdapter(writes: {A}),
          schedule: Schedules.update,
          label: const SystemLabel('x'),
        )
        ..addSystemAdapter(
          AccessAdapter(writes: {A}),
          schedule: Schedules.update,
          label: const SystemLabel('y'),
        );
      app.start();

      expect(messages, hasLength(1));
      expect(messages.single, contains('Access conflict'));
    });

    test('the built-in DespawnAfter ticker is visible to the detector', () {
      // A game system writing DespawnAfter (extending a lifetime) unordered
      // against the built-in ticker is a real frame-order hazard: the write
      // landing before or after the tick shifts the lifetime by one delta.
      final app = _app();
      _add(app, 'powerUp', AccessAdapter(writes: {DespawnAfter}));
      app.start();

      expect(app.accessConflicts, hasLength(1));
      final c = app.accessConflicts.single;
      expect(c.kind, ConflictKind.writeWrite);
      expect(c.component, DespawnAfter);
      expect({c.a.id, c.b.id}, contains(DespawnAfterSystem.label.id));
    });

    test('ordering against DespawnAfterSystem.label resolves the conflict',
        () {
      final app = _app();
      _add(app, 'powerUp', AccessAdapter(writes: {DespawnAfter}),
          after: const [DespawnAfterSystem.label]);
      app.start();

      expect(app.accessConflicts, isEmpty);
    });

    test('hand-written adapters without access never conflict', () {
      // RecordingAdapter-style adapters that do not implement
      // SystemAccessProvider contribute no access and so cannot conflict.
      final app = _app();
      app
        ..addSystemAdapter(
          _NoAccessAdapter(),
          schedule: Schedules.update,
          label: const SystemLabel('a'),
        )
        ..addSystemAdapter(
          _NoAccessAdapter(),
          schedule: Schedules.update,
          label: const SystemLabel('b'),
        );
      app.start();
      expect(app.accessConflicts, isEmpty);
    });
  });
}

final class _NoAccessAdapter implements SystemAdapter {
  @override
  void initialize(World world) {}

  @override
  void run() {}
}
