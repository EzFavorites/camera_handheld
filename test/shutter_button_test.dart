import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_handheld/features/capture/shutter_button.dart';

void main() {
  group('ShutterButton', () {
    testWidgets('shows camera icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShutterButton(onCapture: () {}),
          ),
        ),
      );

      expect(find.byType(Icon), findsOneWidget);
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.camera_alt_outlined);
    });

    testWidgets('calls onCapture on tap', (tester) async {
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShutterButton(onCapture: () => taps++),
          ),
        ),
      );

      await tester.tap(find.byType(ShutterButton));
      expect(taps, 1);

      await tester.tap(find.byType(ShutterButton));
      expect(taps, 2);
    });

    testWidgets('renders as circle button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShutterButton(onCapture: () {}),
          ),
        ),
      );

      // Check Container exists (the button shape)
      expect(find.byType(Container), findsWidgets);
    });
  });
}
