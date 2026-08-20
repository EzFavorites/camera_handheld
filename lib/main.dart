import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/camera_config_store.dart';
import 'core/virtual_protocol.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Load persisted camera config (IP, port, credentials, stream type).
  final config = await CameraConfigStore.load();

  // Use VirtualProtocol for testing without hardware.
  // Replace with IsapiProtocol when connecting to a real Hikvision camera.
  final protocol = VirtualProtocol();

  runApp(CameraApp(
    protocol: protocol,
    initialConfig: config,
  ));
}