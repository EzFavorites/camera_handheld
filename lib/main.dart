import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'app.dart';
import 'core/app_log.dart';
import 'core/camera_config_store.dart';
import 'core/isapi_protocol.dart';
import 'core/ptz_protocol.dart';
import 'core/virtual_protocol.dart';

/// 无硬件演示模式：`flutter run --dart-define=VIRTUAL=true`。
/// 主协议走 VirtualProtocol，云台用 mock ISAPI 响应，适合离线看效果。
const useVirtual = bool.fromEnvironment('VIRTUAL');

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
  var config = await CameraConfigStore.load();
  AppLog.log('main: config loaded ip=${config.ip} port=${config.port} '
      'subStream=${config.useSubStream} ptz=${config.ptz.enabled}');

  if (useVirtual) {
    // 演示模式：强制启用云台并给非空密码，让 mock 走完 Digest 流程返回 200。
    config = config.copyWith(
      ptz: config.ptz.copyWith(enabled: true, password: 'demo'),
    );
    AppLog.log('main: VIRTUAL mode (no hardware) — VirtualProtocol + mocked PTZ');
  }

  // Real control plane via Hikvision ISAPI (Digest auth over HTTP).
  // VirtualProtocol remains available for offline/testing.
  final protocol =
      useVirtual ? VirtualProtocol() : IsapiProtocol(config: config);

  // External PTZ gimbal, only when enabled in config.
  PtzProtocol? ptz;
  if (config.ptz.enabled) {
    ptz = useVirtual
        ? PtzProtocol.forTesting(config.ptz, _mockPtzClient())
        : PtzProtocol(config: config.ptz);
    AppLog.log('main: PTZ enabled${useVirtual ? ' (mocked)' : ''}');
  }

  runApp(CameraApp(
    protocol: protocol,
    initialConfig: config,
    ptzProtocol: ptz,
  ));
}

/// 模拟海康 ISAPI Digest 鉴权：首包 401 + WWW-Authenticate，带 Authorization 后 200。
/// 仅用于 VIRTUAL 演示模式。
http.Client _mockPtzClient() {
  return MockClient((request) async {
    if (request.headers['Authorization'] == null) {
      return http.Response('', 401, headers: {
        'www-authenticate':
            'Digest realm="test", nonce="n1", qop="auth", opaque="o1"',
      });
    }
    return http.Response('OK', 200);
  });
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
