/// Abstract interface for camera protocol operations.
/// VirtualProtocol implements this for testing.
/// Future: IsapiProtocol implements this with real ISAPI HTTP calls.
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

  /// Release all resources.
  void dispose();
}