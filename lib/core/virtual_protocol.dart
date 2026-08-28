import 'app_log.dart';

import 'camera_config.dart';
import 'camera_protocol.dart';

/// Mock protocol implementation for testing without hardware.
/// All operations log via [AppLog] for debugging.
class VirtualProtocol implements CameraProtocol {
  @override
  Future<void> capture() async {
    AppLog.log('[VirtualProtocol] capture triggered');
  }

  @override
  Future<void> zoomIn() async {
    AppLog.log('[VirtualProtocol] zoom IN');
  }

  @override
  Future<void> zoomOut() async {
    AppLog.log('[VirtualProtocol] zoom OUT');
  }

  @override
  Future<void> zoomStop() async {
    AppLog.log('[VirtualProtocol] zoom STOP');
  }

  @override
  Future<void> focusAt(int x, int y) async {
    AppLog.log('[VirtualProtocol] focusAt: ($x, $y)');
  }

  @override
  void updateConfig(CameraConfig config) {
    AppLog.log('[VirtualProtocol] config updated: ${config.ip}');
  }

  @override
  void dispose() {
    AppLog.log('[VirtualProtocol] disposed');
  }
}