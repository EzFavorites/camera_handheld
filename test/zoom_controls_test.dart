import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_handheld/features/lens/zoom_controls.dart';

void main() {
  group('ZoomControls', () {
    testWidgets('shows plus and minus buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZoomControls(
              zoomLevel: 1.0,
              onZoomIn: () {},
              onZoomOut: () {},
              onZoomStop: () {},
            ),
          ),
        ),
      );

      expect(find.text('+'), findsOneWidget);
      expect(find.text('−'), findsOneWidget);
    });

    testWidgets('calls onZoomIn on tap +', (tester) async {
      int count = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZoomControls(
              zoomLevel: 1.0,
              onZoomIn: () => count++,
              onZoomOut: () {},
              onZoomStop: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('+'));
      expect(count, 1);
    });

    testWidgets('calls onZoomOut on tap −', (tester) async {
      int count = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZoomControls(
              zoomLevel: 1.0,
              onZoomIn: () {},
              onZoomOut: () => count++,
              onZoomStop: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('−'));
      expect(count, 1);
    });
  });
}
