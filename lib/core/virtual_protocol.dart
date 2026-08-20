import 'camera_protocol.dart';

/// Mock protocol implementation for testing without hardware.
/// All operations print to console for debugging.
class VirtualProtocol implements CameraProtocol {
  @override
  Future<void> capture() async {
    print('[VirtualProtocol] capture triggered');
  }

  @override
  Future<void> zoomIn() async {
    print('[VirtualProtocol] zoom IN');
  }

  @override
  Future<void> zoomOut() async {
    print('[VirtualProtocol] zoom OUT');
  }

  @override
  Future<void> zoomStop() async {
    print('[VirtualProtocol] zoom STOP');
  }

  @override
  Future<void> focusAt(int x, int y) async {
    print('[VirtualProtocol] focusAt: ($x, $y)');
  }

  @override
  void dispose() {
    print('[VirtualProtocol] disposed');
  }
}