import 'package:flutter_test/flutter_test.dart';
import 'package:camera_handheld/core/camera_protocol.dart';
import 'package:camera_handheld/core/virtual_protocol.dart';

void main() {
  group('VirtualProtocol', () {
    late VirtualProtocol protocol;

    setUp(() {
      protocol = VirtualProtocol();
    });

    test('implements CameraProtocol', () {
      expect(protocol, isA<CameraProtocol>());
    });

    test('capture does not throw', () async {
      await expectLater(protocol.capture(), completes);
    });

    test('zoomIn does not throw', () async {
      await expectLater(protocol.zoomIn(), completes);
    });

    test('zoomOut does not throw', () async {
      await expectLater(protocol.zoomOut(), completes);
    });

    test('zoomStop does not throw', () async {
      await expectLater(protocol.zoomStop(), completes);
    });

    test('focusAt does not throw', () async {
      await expectLater(protocol.focusAt(500, 500), completes);
    });

    test('dispose does not throw', () {
      expect(() => protocol.dispose(), returnsNormally);
    });

    test('works with empty config', () {
      // The protocol should work regardless of config
      expect(() => protocol.dispose(), returnsNormally);
    });
  });
}
