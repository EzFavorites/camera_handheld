import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_handheld/features/preview/focus_overlay.dart';

void main() {
  group('FocusOverlay', () {
    testWidgets('returns empty widget when not visible', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FocusOverlay(
              visible: false,
              focusX: 500,
              focusY: 500,
              viewSize: const Size(1920, 1080),
            ),
          ),
        ),
      );

      // No visible content when hidden
      expect(find.text('500, 500'), findsNothing);
    });

    testWidgets('shows coordinates when visible', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FocusOverlay(
              visible: true,
              focusX: 300,
              focusY: 700,
              viewSize: const Size(1920, 1080),
            ),
          ),
        ),
      );

      expect(find.text('300, 700'), findsOneWidget);
    });

    testWidgets('maps normalized coords to pixels', (tester) async {
      // At 1000x1000 on 1920x1080 -> should be at bottom-right
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FocusOverlay(
              visible: true,
              focusX: 1000,
              focusY: 1000,
              viewSize: const Size(1920, 1080),
            ),
          ),
        ),
      );

      expect(find.text('1000, 1000'), findsOneWidget);
    });
  });
}
