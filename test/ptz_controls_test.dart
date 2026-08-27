import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_handheld/features/ptz/ptz_controls.dart';

void main() {
  Future<void> pumpPtz(
    WidgetTester t, {
    bool enabled = true,
    ValueChanged<PtzDirection>? onMove,
    VoidCallback? onStop,
  }) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PtzControls(
          enabled: enabled,
          tapStopDelayMs: 60,
          onMove: onMove ?? (_) {},
          onStop: onStop ?? () {},
        ),
      ),
    ));
  }

  testWidgets('renders 4 direction buttons when enabled', (t) async {
    await pumpPtz(t);
    expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    expect(find.byIcon(Icons.arrow_left), findsOneWidget);
    expect(find.byIcon(Icons.arrow_right), findsOneWidget);
  });

  testWidgets('renders nothing when disabled', (t) async {
    await pumpPtz(t, enabled: false);
    expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    expect(find.byIcon(Icons.arrow_left), findsNothing);
    expect(find.byIcon(Icons.arrow_right), findsNothing);
  });

  testWidgets('long press up triggers move up', (t) async {
    final moves = <PtzDirection>[];
    await pumpPtz(t, onMove: moves.add);
    final upBtn = find.byIcon(Icons.arrow_drop_up);
    final gesture = await t.startGesture(t.getCenter(upBtn));
    await t.pump(const Duration(milliseconds: 600)); // 超过长按阈值
    expect(moves, contains(PtzDirection.up));
    await gesture.up();
    await t.pumpAndSettle();
  });

  testWidgets('long press release triggers stop', (t) async {
    final moves = <PtzDirection>[];
    var stops = 0;
    await pumpPtz(t, onMove: moves.add, onStop: () => stops++);
    final upBtn = find.byIcon(Icons.arrow_drop_up);
    final gesture = await t.startGesture(t.getCenter(upBtn));
    await t.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await t.pumpAndSettle();
    expect(moves, contains(PtzDirection.up));
    expect(stops, 1);
  });

  testWidgets('tap up triggers move up then stop after delay', (t) async {
    final moves = <PtzDirection>[];
    var stops = 0;
    await pumpPtz(t, onMove: moves.add, onStop: () => stops++);
    await t.tap(find.byIcon(Icons.arrow_drop_up));
    await t.pump(const Duration(milliseconds: 200)); // 超过 tapStopDelayMs(60)
    expect(moves, contains(PtzDirection.up));
    expect(stops, 1);
    await t.pumpAndSettle();
  });

  testWidgets('tap down triggers move down', (t) async {
    final moves = <PtzDirection>[];
    var stops = 0;
    await pumpPtz(t, onMove: moves.add, onStop: () => stops++);
    await t.tap(find.byIcon(Icons.arrow_drop_down));
    await t.pump(const Duration(milliseconds: 200));
    expect(moves, contains(PtzDirection.down));
    expect(stops, 1);
    await t.pumpAndSettle();
  });
}
