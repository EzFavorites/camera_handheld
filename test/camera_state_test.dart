import 'package:camera_handheld/core/camera_config.dart';
import 'package:camera_handheld/core/virtual_protocol.dart';
import 'package:camera_handheld/features/camera_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CameraState state;

  setUp(() {
    state = CameraState(protocol: VirtualProtocol(), config: const CameraConfig());
  });

  tearDown(() {
    state.dispose();
  });

  test('capture toggles isCapturing and settles back to false', () async {
    expect(state.isCapturing, isFalse);
    final future = state.capture();
    expect(state.isCapturing, isTrue);
    await future;
    expect(state.isCapturing, isFalse);
  });

  test('capture resets isCapturing even if protocol throws', () async {
    // VirtualProtocol never throws, but verify the finally-path via a throwing protocol.
    final throwing = _ThrowingProtocol();
    final s = CameraState(protocol: throwing, config: const CameraConfig());
    // Error propagates, but isCapturing must still settle back to false.
    await expectLater(s.capture(), throwsA(isA<Exception>()));
    expect(s.isCapturing, isFalse);
    s.dispose();
  });

  test('zoomIn clamps to [1.0, 32.0]', () {
    for (var i = 0; i < 500; i++) {
      state.zoomIn();
    }
    expect(state.zoomLevel, 32.0);

    for (var i = 0; i < 500; i++) {
      state.zoomOut();
    }
    expect(state.zoomLevel, 1.0);
  });

  test('focusAt clamps coordinates to 0..1000 and shows focus', () {
    state.focusAt(5000, -50);
    expect(state.focusX, 1000);
    expect(state.focusY, 0);
    expect(state.showFocus, isTrue);
  });

  test('updateConfig bumps configVersion', () {
    final before = state.configVersion;
    state.updateConfig(const CameraConfig(ip: '10.0.0.9'));
    expect(state.configVersion, before + 1);
    expect(state.config.ip, '10.0.0.9');
  });

  test('connection status transitions', () {
    expect(state.connectionStatus, 'disconnected');
    state.setConnected();
    expect(state.connectionStatus, 'connected');
    state.setDisconnected();
    expect(state.connectionStatus, 'disconnected');
  });
}

class _ThrowingProtocol extends VirtualProtocol {
  @override
  Future<void> capture() async => throw Exception('boom');
}
