import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/app_log.dart';
import 'core/camera_config_store.dart';
import 'core/isapi_protocol.dart';
import 'core/ptz_protocol.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Boot the file logger BEFORE anything else: uncaught errors below and
  // during the run are persisted to disk so a hard crash can be post-mortemed.
  await AppLog.init();
  _installErrorHooks();
  AppLog.log('main: booting on ${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion}; media_kit init next');

  MediaKit.ensureInitialized();
  AppLog.log('main: MediaKit ready');

  // Load persisted camera config (IP, port, credentials, stream type).
  final config = await CameraConfigStore.load();
  AppLog.log('main: config loaded ip=${config.ip} port=${config.port} '
      'subStream=${config.useSubStream} ptz=${config.ptz.enabled}');

  // Real control plane via Hikvision ISAPI (Digest auth over HTTP).
  // VirtualProtocol remains available for offline/testing.
  final protocol = IsapiProtocol(config: config);

  // External PTZ gimbal, only when enabled in config.
  PtzProtocol? ptz;
  if (config.ptz.enabled) {
    ptz = PtzProtocol(config: config.ptz);
    AppLog.log('main: PTZ enabled');
  }

  runApp(CameraApp(
    protocol: protocol,
    initialConfig: config,
    ptzProtocol: ptz,
  ));
}

/// Route uncaught framework and async errors into the on-disk log so a crash
/// leaves a trace even in release builds on Windows.
void _installErrorHooks() {
  // Framework errors (build/layout/assertion) — also keeps the default
  // red-screen in debug via [FlutterError.presentError].
  FlutterError.onError = (details) {
    AppLog.recordError(details.exception, details.stack,
        context: 'FlutterError');
    FlutterError.presentError(details);
  };

  // Any uncaught error from the framework's task queue / microtasks.
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.recordError(error, stack, context: 'uncaught');
    return true; // suppress the default silent exit
  };
}
