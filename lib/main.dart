import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/camera_config_store.dart';
import 'core/isapi_protocol.dart';
import 'core/ptz_protocol.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Load persisted camera config (IP, port, credentials, stream type).
  final config = await CameraConfigStore.load();

  // Real control plane via Hikvision ISAPI (Digest auth over HTTP).
  // VirtualProtocol remains available for offline/testing.
  final protocol = IsapiProtocol(config: config);

  // External PTZ gimbal, only when enabled in config.
  PtzProtocol? ptz;
  if (config.ptz.enabled) {
    ptz = PtzProtocol(config: config.ptz);
  }

  runApp(CameraApp(
    protocol: protocol,
    initialConfig: config,
    ptzProtocol: ptz,
  ));
}
