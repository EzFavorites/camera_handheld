import 'package:flutter/foundation.dart';
import '../core/camera_config.dart';
import '../core/camera_protocol.dart';

/// Shared camera state, consumed by UI via Provider.
class CameraState extends ChangeNotifier {
  final CameraProtocol protocol;
  CameraConfig config;

  CameraState({required this.protocol, required this.config});

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
    } finally {
      _isCapturing = false;
      notifyListeners();
    }
  }

  Future<void> zoomIn() async {
    _zoomLevel = (_zoomLevel + 0.1).clamp(1.0, 32.0);
    notifyListeners();
    await protocol.zoomIn();
  }

  Future<void> zoomOut() async {
    _zoomLevel = (_zoomLevel - 0.1).clamp(1.0, 32.0);
    notifyListeners();
    await protocol.zoomOut();
  }

  Future<void> zoomStop() async {
    await protocol.zoomStop();
  }

  Future<void> focusAt(int x, int y) async {
    _focusX = x.clamp(0, 1000);
    _focusY = y.clamp(0, 1000);
    _showFocus = true;
    notifyListeners();
    await protocol.focusAt(_focusX, _focusY);
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
    notifyListeners();
  }

  void setStreamInfo(String info) {
    _streamInfo = info;
    notifyListeners();
  }

  @override
  void dispose() {
    protocol.dispose();
    super.dispose();
  }
}