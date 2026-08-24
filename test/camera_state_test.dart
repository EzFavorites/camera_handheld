import 'package:flutter_test/flutter_test.dart';
import 'package:camera_handheld/core/camera_config.dart';
import 'package:camera_handheld/core/virtual_protocol.dart';
import 'package:camera_handheld/features/camera_state.dart';

void main() {
  group('CameraState', () {
    late CameraState state;
    late VirtualProtocol protocol;

    setUp(() {
      protocol = VirtualProtocol();
      state = CameraState(protocol: protocol, config: const CameraConfig());
    });

    tearDown(() {
      state.dispose();
    });

    test('initial state', () {
      expect(state.zoomLevel, 1.0);
      expect(state.isCapturing, isFalse);
      expect(state.connectionStatus, 'disconnected');
      expect(state.streamInfo, '');
      expect(state.focusX, 500);
      expect(state.focusY, 500);
      expect(state.showFocus, isFalse);
    });

    test('zoom in increases level up to 32.0', () async {
      // Call zoomIn sequentially to allow each to complete
      for (var i = 0; i < 320; i++) {
        await state.zoomIn();
      }
      expect(state.zoomLevel, greaterThan(1.0));
      expect(state.zoomLevel, lessThanOrEqualTo(32.0));
    });

    test('zoom out decreases level down to 1.0', () async {
      // Zoom in first
      for (var i = 0; i < 100; i++) {
        await state.zoomIn();
      }
      final before = state.zoomLevel;
      await state.zoomOut();
      expect(state.zoomLevel, lessThan(before));
      expect(state.zoomLevel, greaterThanOrEqualTo(1.0));
    });

    test('zoom level clamped at 1.0 minimum', () async {
      // Start at 1.0 and zoom out
      await state.zoomOut();
      expect(state.zoomLevel, 1.0);
    });

    test('zoom level clamped at 32.0 maximum', () async {
      // Zoom in many times
      for (var i = 0; i < 400; i++) {
        await state.zoomIn();
      }
      expect(state.zoomLevel, lessThanOrEqualTo(32.0));
      expect(state.zoomLevel, greaterThanOrEqualTo(31.0));
    });

    test('capture sets isCapturing during operation', () async {
      bool captured = false;
      state.addListener(() {
        if (state.isCapturing) captured = true;
      });
      await state.capture();
      expect(captured, isTrue);
    });

    test('focusAt normalizes coordinates to 0-1000', () async {
      await state.focusAt(-100, -200);
      expect(state.focusX, 0);
      expect(state.focusY, 0);
      expect(state.showFocus, isTrue);

      await state.focusAt(2000, 2000);
      expect(state.focusX, 1000);
      expect(state.focusY, 1000);

      await state.focusAt(500, 500);
      expect(state.focusX, 500);
      expect(state.focusY, 500);
    });

    test('hideFocus clears focus display', () async {
      await state.focusAt(500, 500);
      expect(state.showFocus, isTrue);
      state.hideFocus();
      expect(state.showFocus, isFalse);
    });

    test('setConnected sets status', () {
      state.setConnected();
      expect(state.connectionStatus, 'connected');
    });

    test('setDisconnected sets status', () {
      state.setDisconnected();
      expect(state.connectionStatus, 'disconnected');
    });

    test('setStreamInfo updates info', () {
      state.setStreamInfo('子码流');
      expect(state.streamInfo, '子码流');
    });

    test('updateConfig bumps configVersion', () {
      final oldVersion = state.configVersion;
      state.updateConfig(const CameraConfig(ip: '192.168.1.100'));
      expect(state.configVersion, greaterThan(oldVersion));
    });

    test('updateConfig updates config', () {
      state.updateConfig(const CameraConfig(ip: '10.0.0.5'));
      expect(state.config.ip, '10.0.0.5');
    });

    test('configVersion change triggers listener', () {
      int count = 0;
      state.addListener(() => count++);
      state.updateConfig(const CameraConfig(ip: '1.2.3.4'));
      expect(count, greaterThan(0));
    });
  });
}
