import 'camera_config.dart';

/// Abstract interface for camera protocol operations.
/// VirtualProtocol implements this for testing.
/// IsapiProtocol implements this with real ISAPI HTTP calls.
abstract class CameraProtocol {
  /// Capture a still image from the camera.
  Future<void> capture();

  /// Start zooming in (tele).
  Future<void> zoomIn();

  /// Start zooming out (wide).
  Future<void> zoomOut();

  /// Stop zoom motion.
  Future<void> zoomStop();

  /// Set focus point at normalized coordinates (0-1000).
  Future<void> focusAt(int x, int y);

  /// Update the camera config (IP, credentials, etc.) at runtime.
  /// Called when the user changes settings.
  void updateConfig(CameraConfig config);

  /// Release all resources.
  void dispose();
}