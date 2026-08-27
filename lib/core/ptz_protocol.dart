import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'digest_auth.dart';
import 'ptz_config.dart';

/// 外接云台 ISAPI 协议。PTZ 走 continuous 接口。
/// 请求经串行队列，避免快速点击冻结 UI。
class PtzProtocol {
  PtzConfig config;
  final http.Client _client;
  final bool _ownsClient;
  String? _cnonce;
  int _nc = 0;
  bool _isLocked = false;

  Future<void> _chain = Future.value();

  PtzProtocol({required this.config})
      : _client = http.Client(),
        _ownsClient = true;

  /// 测试构造函数：注入 http client。
  PtzProtocol.forTesting(this.config, http.Client client)
      : _client = client,
        _ownsClient = false;

  void _log(String msg) => AppLog.log('[PTZ] $msg');

  Future<T> _enqueue<T>(Future<T> Function() task,
      {Duration timeout = const Duration(seconds: 5)}) {
    final completer = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        final result = await task().timeout(timeout, onTimeout: () {
          throw TimeoutException('PTZ request timed out');
        });
        if (!completer.isCompleted) completer.complete(result);
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });
    return completer.future;
  }

  bool _checkLocked(String body) {
    if (body.toLowerCase().contains('device is locked')) {
      _isLocked = true;
      _log('DEVICE LOCKED!');
      return true;
    }
    return false;
  }

  Future<http.Response> _request(
    String method,
    String path, {
    String? body,
    String contentType = 'application/xml',
  }) {
    return _enqueue(() async {
      if (_isLocked) {
        throw StateError('PTZ device is locked. Wait and retry.');
      }
      final uri = Uri.parse('http://${config.ip}$path');
      _nc = 0;
      _log('$method $path');

      final req1 = http.Request(method, uri);
      if (body != null) req1.body = body;
      req1.headers['Content-Type'] = contentType;
      final resp1 = await _client.send(req1).timeout(const Duration(seconds: 5));
      final body1 = await resp1.stream.bytesToString();

      if (_checkLocked(body1)) return http.Response(body1, resp1.statusCode);

      if (resp1.statusCode != 401) {
        _log('$path → ${resp1.statusCode} (no auth)');
        return http.Response(body1, resp1.statusCode);
      }

      if (config.password.isEmpty) {
        throw HttpException('PTZ password empty. Configure in Settings.');
      }

      final authHeader = resp1.headers['www-authenticate'] ?? '';
      final params = DigestAuth.parseParams(authHeader);
      if (params.isEmpty) {
        _log('$path → failed to parse WWW-Authenticate');
        return http.Response(body1, resp1.statusCode);
      }

      _cnonce ??= DigestAuth.generateCnonce();
      _nc++;
      final digest = DigestAuth(username: 'admin', password: config.password);
      final auth = digest.buildHeader(
        method: method,
        uriPath: uri.path,
        params: params,
        cnonce: _cnonce!,
        nc: _nc,
      );

      final req2 = http.Request(method, uri);
      if (body != null) req2.body = body;
      req2.headers['Content-Type'] = contentType;
      req2.headers['Authorization'] = auth;
      final resp2 = await _client.send(req2).timeout(const Duration(seconds: 5));
      final body2 = await resp2.stream.bytesToString();
      if (_checkLocked(body2)) return http.Response(body2, resp2.statusCode);
      _log('$path → ${resp2.statusCode}');
      return http.Response(body2, resp2.statusCode);
    });
  }

  /// 发送 continuous PTZ。pan/tilt/zoom 为 -1.0..1.0 方向值（已含符号），
  /// 内部乘 config.normalizedSpeed 下发。
  Future<void> move({required double pan, required double tilt, required double zoom}) {
    final s = config.normalizedSpeed;
    final body = '<PTZData>'
        '<pan>${_fmt(pan * s)}</pan>'
        '<tilt>${_fmt(tilt * s)}</tilt>'
        '<zoom>${_fmt(zoom * s)}</zoom>'
        '</PTZData>';
    return _request('PUT', '/ISAPI/PTZCtrl/channels/1/continuous', body: body)
        .then((r) {
      if (r.statusCode != 200) {
        _log('move → HTTP ${r.statusCode}');
      }
    });
  }

  /// 格式化为设备接受的浮点（去尾零，避免 0.50e0 之类）。
  String _fmt(double v) {
    if (v == 0) return '0';
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  Future<void> stop() => move(pan: 0, tilt: 0, zoom: 0);

  Future<void> zoomIn() => move(pan: 0, tilt: 0, zoom: 1);
  Future<void> zoomOut() => move(pan: 0, tilt: 0, zoom: -1);
  Future<void> zoomStop() => stop();

  // ── 方向便捷方法 ──
  // 海康坐标系：pan 正=右 负=左；tilt 正=下 负=上
  Future<void> up() => move(pan: 0, tilt: -1, zoom: 0);
  Future<void> down() => move(pan: 0, tilt: 1, zoom: 0);
  Future<void> left() => move(pan: -1, tilt: 0, zoom: 0);
  Future<void> right() => move(pan: 1, tilt: 0, zoom: 0);

  void updateConfig(PtzConfig newConfig) {
    config = newConfig;
    _isLocked = false;
    _cnonce = null;
    _nc = 0;
    _log('Config updated: ${config.ip}, pwd=${config.password.isEmpty ? "(empty)" : "(set)"}');
  }

  /// 连通性自检（设置页用）。成功返回 null，失败返回错误描述。
  static Future<String?> testConnection(PtzConfig config) async {
    AppLog.log('[PTZ] Testing connection to ${config.ip}...');
    final client = http.Client();
    try {
      final uri = Uri.parse('http://${config.ip}/ISAPI/System/deviceInfo');
      final req1 = http.Request('GET', uri);
      final resp1 = await client.send(req1).timeout(const Duration(seconds: 5));
      final body1 = await resp1.stream.bytesToString();
      if (body1.toLowerCase().contains('device is locked')) {
        return '云台设备已锁定，请稍后重试。';
      }
      if (resp1.statusCode != 401) {
        AppLog.log('[PTZ] Connection OK (no auth)');
        return null;
      }
      if (config.password.isEmpty) {
        return '云台密码为空，请在设置中填写。';
      }
      final params = DigestAuth.parseParams(resp1.headers['www-authenticate'] ?? '');
      if (params.isEmpty) return '无法解析认证头。';
      final cnonce = DigestAuth.generateCnonce();
      final digest = DigestAuth(username: 'admin', password: config.password);
      final auth = digest.buildHeader(
        method: 'GET',
        uriPath: '/ISAPI/System/deviceInfo',
        params: params,
        cnonce: cnonce,
        nc: 1,
      );
      final req2 = http.Request('GET', uri);
      req2.headers['Authorization'] = auth;
      final resp2 = await client.send(req2).timeout(const Duration(seconds: 5));
      final body2 = await resp2.stream.bytesToString();
      if (body2.toLowerCase().contains('device is locked')) {
        return '云台设备已锁定，请稍后重试。';
      }
      if (resp2.statusCode == 200) {
        AppLog.log('[PTZ] Connection OK (auth success)');
        return null;
      }
      if (resp2.statusCode == 401) return '云台认证失败，请检查密码。';
      return '云台异常响应: HTTP ${resp2.statusCode}';
    } on TimeoutException {
      return '云台连接超时，请检查网络。';
    } on SocketException {
      return '无法连接云台 ${config.ip}，请检查网络。';
    } catch (e) {
      return '云台连接错误: $e';
    } finally {
      client.close();
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
