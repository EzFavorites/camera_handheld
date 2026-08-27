import 'package:flutter/foundation.dart';
import '../core/camera_config.dart';
import '../core/camera_protocol.dart';
import '../core/ptz_protocol.dart';

/// Shared camera state, consumed by UI via Provider.
class CameraState extends ChangeNotifier {
  final CameraProtocol protocol;
  /// External PTZ gimbal protocol. Null when disabled/not wired.
  final PtzProtocol? ptzProtocol;
  CameraConfig config;

  CameraState({
    required this.protocol,
    required this.config,
    this.ptzProtocol,
  });

  int _configVersion = 0;
  int get configVersion => _configVersion;

  double _zoomLevel = 1.0;
  double get zoomLevel => _zoomLevel;

  bool _isCapturing = false;
  bool get isCapturing => _isCapturing;

  String _connectionStatus = 'disconnected';
  String get connectionStatus => _connectionStatus;

  String _streamInfo = '';
  String get streamInfo => _streamInfo;

  int _focusX = 500;
  int _focusY = 500;
  int get focusX => _focusX;
  int get focusY => _focusY;

  bool _showFocus = false;
  bool get showFocus => _showFocus;

  Future<void> capture() async {
    _isCapturing = true;
    notifyListeners();
    try {
      await protocol.capture();
    } catch (e) {
      debugPrint('[CameraState] capture error: $e');
    } finally {
      _isCapturing = false;
      notifyListeners();
    }
  }

  Future<void> zoomIn() async {
    _zoomLevel = (_zoomLevel + 0.1).clamp(1.0, 32.0);
    notifyListeners();
    // Fire-and-forget: command queue handles serialization, errors logged not thrown
    protocol.zoomIn().catchError((e) => debugPrint('[CameraState] zoomIn error: $e'));
    _relayPtzZoom(1);
  }

  Future<void> zoomOut() async {
    _zoomLevel = (_zoomLevel - 0.1).clamp(1.0, 32.0);
    notifyListeners();
    protocol.zoomOut().catchError((e) => debugPrint('[CameraState] zoomOut error: $e'));
    _relayPtzZoom(-1);
  }

  Future<void> zoomStop() async {
    protocol.zoomStop().catchError((e) => debugPrint('[CameraState] zoomStop error: $e'));
    _relayPtzStop();
  }

  /// Relay main-camera zoom to the PTZ gimbal so both lenses track together.
  /// Fire-and-forget: a gimbal failure must never break the main camera flow.
  void _relayPtzZoom(int dir) {
    final ptz = ptzProtocol;
    if (ptz == null || !config.ptz.enabled) return;
    final f = dir > 0 ? ptz.zoomIn() : ptz.zoomOut();
    f.catchError((e) => debugPrint('[CameraState] ptz zoom relay error: $e'));
  }

  void _relayPtzStop() {
    final ptz = ptzProtocol;
    if (ptz == null || !config.ptz.enabled) return;
    ptz.zoomStop().catchError((e) => debugPrint('[CameraState] ptz stop relay error: $e'));
  }

  Future<void> focusAt(int x, int y) async {
    _focusX = x.clamp(0, 1000);
    _focusY = y.clamp(0, 1000);
    _showFocus = true;
    notifyListeners();
    try {
      await protocol.focusAt(_focusX, _focusY);
    } catch (e) {
      debugPrint('[CameraState] focusAt error: $e');
    }
  }

  void hideFocus() {
    _showFocus = false;
    notifyListeners();
  }

  void setConnected() {
    _connectionStatus = 'connected';
    notifyListeners();
  }

  void setDisconnected() {
    _connectionStatus = 'disconnected';
    notifyListeners();
  }

  void updateConfig(CameraConfig newConfig) {
    config = newConfig;
    _configVersion++;
    protocol.updateConfig(newConfig);
    if (ptzProtocol != null) {
      ptzProtocol!.updateConfig(newConfig.ptz);
    }
    notifyListeners();
  }

  void setStreamInfo(String info) {
    _streamInfo = info;
    notifyListeners();
  }

  @override
  void dispose() {
    protocol.dispose();
    ptzProtocol?.dispose();
    super.dispose();
  }
}