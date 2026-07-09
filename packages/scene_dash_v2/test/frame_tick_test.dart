import 'package:flutter_test/flutter_test.dart';
import 'package:scene_dash_v2_core/advanced.dart';
// FrameTickNotifier is the internal type Game exposes only as a Listenable;
// reach into src to drive it directly (a live Game needs Flutter GPU — see the
// skipped Game.shutdown test in scene_driver_test.dart).
import 'package:scene_dash_v2/src/frame_tick.dart';

import 'support.dart';

void main() {
  test('pulses listeners once per frame end (as Game wires it at onFrameEnd)',
      () {
    final tick = FrameTickNotifier();
    var pulses = 0;
    tick.addListener(() => pulses++);

    // Wired exactly as Game wires it: the loop invokes onFrameEnd at the end of
    // update, once per frame regardless of how many fixed steps ran.
    final app = App();
    final loop = EcsFrameLoop(app, onFrameEnd: tick.pulse)
      ..ensureTimeResources();
    app.start();

    loop.update(0.016);
    expect(pulses, 1);
    loop
      ..fixedStep(1 / 60)
      ..fixedStep(1 / 60)
      ..update(0.016);
    expect(pulses, 2, reason: 'one pulse per frame, not per fixed step');
  });

  test('fires after renderSync, so listeners read a fully-resolved frame', () {
    final log = <String>[];
    final tick = FrameTickNotifier()..addListener(() => log.add('tick'));
    final app = App()
      ..addSystemAdapter(
        CountAdapter('renderSync', log),
        schedule: Schedules.renderSync,
        label: const SystemLabel('p.renderSync'),
      );
    final loop = EcsFrameLoop(app, onFrameEnd: tick.pulse)
      ..ensureTimeResources();
    app.start();

    loop.update(0.016);
    expect(log, <String>['renderSync', 'tick']);
  });

  test('dispose releases listeners', () {
    final tick = FrameTickNotifier();
    var pulses = 0;
    tick.addListener(() => pulses++);
    tick.dispose();
    // A disposed notifier throws if pulsed again — Game only pulses while the
    // driver is attached, and disposes at shutdown after detaching it.
    expect(() => tick.pulse(), throwsA(isA<Object>()));
    expect(pulses, 0);
  });
}
