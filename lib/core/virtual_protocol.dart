import 'package:flutter/foundation.dart';

import 'camera_protocol.dart';

/// Mock protocol implementation for testing without hardware.
/// All operations print to console for debugging.
class VirtualProtocol implements CameraProtocol {
  @override
  Future<void> capture() async {
    debugPrint('[VirtualProtocol] capture triggered');
  }

  @override
  Future<void> zoomIn() async {
    debugPrint('[VirtualProtocol] zoom IN');
  }

  @override
  Future<void> zoomOut() async {
    debugPrint('[VirtualProtocol] zoom OUT');
  }

  @override
  Future<void> zoomStop() async {
    debugPrint('[VirtualProtocol] zoom STOP');
  }

  @override
  Future<void> focusAt(int x, int y) async {
    debugPrint('[VirtualProtocol] focusAt: ($x, $y)');
  }

  @override
  void dispose() {
    debugPrint('[VirtualProtocol] disposed');
  }
}
