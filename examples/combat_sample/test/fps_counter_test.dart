/// The frame-rate readout.
///
/// Worth a test for one reason: the counter shipped broken and stuck at
/// 0, because its `Ticker` lived in a `late final` initialiser. A `late`
/// field is constructed on first READ, and nothing read the ticker except
/// `dispose` — so it was never started and never ticked. Nothing about
/// that is visible in the source; only running it shows it.
library;

import 'package:combat_sample/hud/fps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [frames] frames [frameTime] apart and returns the number the
/// counter is showing.
Future<String> readAfter(
  WidgetTester tester, {
  required int frames,
  Duration frameTime = const Duration(milliseconds: 16),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(frameTime);
  }
  return (tester.widget<Text>(find.byType(Text))).data!;
}

void main() {
  testWidgets('the ticker runs and the counter leaves zero', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FpsCounter())),
    );

    expect(find.text('0 FPS'), findsOneWidget, reason: 'nothing sampled yet');

    // Past the sample window at ~60 fps.
    final reading = await readAfter(tester, frames: 40);

    expect(reading, isNot('0 FPS'), reason: 'the ticker actually ticked');
    expect(reading, endsWith(' FPS'));
  });

  testWidgets('it reports the rate it is actually pumped at', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FpsCounter())),
    );

    // 20ms a frame is 50 fps. Pumped well past the window so the reading
    // is a full window's worth rather than the first partial one.
    final reading = await readAfter(
      tester,
      frames: 80,
      frameTime: const Duration(milliseconds: 20),
    );

    final fps = int.parse(reading.split(' ').first);
    expect(
      fps,
      inInclusiveRange(45, 55),
      reason: '20ms frames are 50fps, allowing for window edges',
    );
  });

  testWidgets('disposing stops the ticker without complaint', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FpsCounter())),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // A live ticker left running past dispose fails the test binding.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    expect(find.byType(FpsCounter), findsNothing);
  });
}
