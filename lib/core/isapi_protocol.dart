import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'camera_config.dart';
import 'camera_protocol.dart';
import 'init_command.dart';

/// ISAPI protocol implementation for Hikvision cameras.
class IsapiProtocol implements CameraProtocol {
  CameraConfig config;
  final http.Client _client = http.Client();
  String? _cnonce;
  int _nc = 0;
  bool _initialized = false;
  bool _isLocked = false;

  final String? _zoomInCmd;
  final String? _zoomOutCmd;
  final String? _zoomStopCmd;

  IsapiProtocol({required this.config})
      : _zoomInCmd = null,
        _zoomOutCmd = null,
        _zoomStopCmd = null;

  IsapiProtocol.withVisca({
    required this.config,
    String? this._zoomInCmd,
    String? this._zoomOutCmd,
    String? this._zoomStopCmd,
  });

  // ── Logging ─────────────────────────────────────────────────

  void _log(String msg) {
    AppLog.log('[ISAPI] $msg');
  }

  // ── Digest auth ─────────────────────────────────────────────

  static String _md5(String data) => md5.convert(utf8.encode(data)).toString();

  /// Sends a request with Digest auth.
  Future<http.Response> _request(
    String method,
    String path, {
    String? body,
    String contentType = 'application/json',
  }) async {
    if (_isLocked) {
      throw HttpException(
        'Device is locked due to too many failed login attempts. '
        'Please wait and try again later.',
      );
    }

    final uri = Uri.parse('${config.httpUrl}$path');
    _nc = 0;
    _log('$method $path');

    // 1st request: no auth.
    final req1 = http.Request(method, uri);
    if (body != null) req1.body = body;
    req1.headers['Content-Type'] = contentType;
    final resp1 = await _client.send(req1);
    final body1 = await resp1.stream.bytesToString();

    if (_checkLocked(body1)) return http.Response(body1, resp1.statusCode);

    if (resp1.statusCode != 401) {
      _log('$path → ${resp1.statusCode} (no auth needed)');
      return http.Response(body1, resp1.statusCode);
    }
    _log('$path → 401, building Digest auth...');

    if (config.password.isEmpty) {
      throw HttpException('Camera password is empty. Please configure it in Settings.');
    }

    // Parse WWW-Authenticate header.
    final authHeader = resp1.headers['www-authenticate'] ?? '';
    final params = _parseDigestParams(authHeader);
    if (params.isEmpty) {
      _log('$path → failed to parse WWW-Authenticate');
      return http.Response(body1, resp1.statusCode);
    }

    final realm = params['realm'] ?? '';
    final nonce = params['nonce'] ?? '';
    final opaque = params['opaque'] ?? '';
    final qop = params['qop'] ?? '';
    _cnonce ??= _generateCnonce();
    _nc++;
    final ncStr = _nc.toString().padLeft(8, '0');

    final ha1 = _md5('${config.username}:$realm:${config.password}');
    final ha2 = _md5('$method:${uri.path}');
    final response = _md5('$ha1:$nonce:$ncStr:$_cnonce:$qop:$ha2');
    _log('Digest: username=${config.username}, realm=$realm, nc=$ncStr');

    final auth = StringBuffer('Digest ');
    auth.write('username="${config.username}", ');
    auth.write('realm="$realm", ');
    auth.write('nonce="$nonce", ');
    auth.write('uri="${uri.path}", ');
    auth.write('qop=$qop, ');
    auth.write('nc=$ncStr, ');
    auth.write('cnonce="$_cnonce", ');
    auth.write('response="$response"');
    if (opaque.isNotEmpty) {
      auth.write(', opaque="$opaque"');
    }

    final req2 = http.Request(method, uri);
    if (body != null) req2.body = body;
    req2.headers['Content-Type'] = contentType;
    req2.headers['Authorization'] = auth.toString();
    final resp2 = await _client.send(req2);
    final body2 = await resp2.stream.bytesToString();

    if (_checkLocked(body2)) return http.Response(body2, resp2.statusCode);

    _log('$path → ${resp2.statusCode}');
    return http.Response(body2, resp2.statusCode);
  }

  bool _checkLocked(String body) {
    if (body.toLowerCase().contains('device is locked')) {
      _isLocked = true;
      _log('DEVICE LOCKED!');
      return true;
    }
    return false;
  }

  Map<String, String> _parseDigestParams(String header) {
    final params = <String, String>{};
    final h = header.replaceFirst(RegExp(r'^Digest\s+', caseSensitive: false), '');
    for (final match in RegExp(r'(\w+)\s*=\s*"([^"]*)"').allMatches(h)) {
      params[match.group(1)!] = match.group(2)!;
    }
    return params;
  }

  String _generateCnonce() {
    final rng = Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return base64Encode(bytes);
  }

  // ── Connection test (static, for settings screen) ───────────

  /// Tests the connection to the camera with the given [config].
  /// Returns `null` on success, or an error message on failure.
  /// This is used by the settings screen to verify credentials before saving.
  static Future<String?> testConnection(CameraConfig config) async {
    AppLog.log('[ISAPI] Testing connection to ${config.ip}...');
    final client = http.Client();
    try {
      final uri = Uri.parse('${config.httpUrl}/ISAPI/System/deviceInfo');

      // 1st request: no auth.
      final req1 = http.Request('GET', uri);
      final resp1 = await client.send(req1);
      final body1 = await resp1.stream.bytesToString();

      if (body1.toLowerCase().contains('device is locked')) {
        return 'Device is locked. Please wait and try again later.';
      }

      if (resp1.statusCode != 401) {
        AppLog.log('[ISAPI] Connection OK (no auth required)');
        return null;
      }

      if (config.password.isEmpty) {
        return 'Password is empty. Please enter a password.';
      }

      // Parse WWW-Authenticate.
      final authHeader = resp1.headers['www-authenticate'] ?? '';
      final params = <String, String>{};
      for (final match in RegExp(r'(\w+)\s*=\s*"([^"]*)"').allMatches(authHeader)) {
        params[match.group(1)!] = match.group(2)!;
      }

      final realm = params['realm'] ?? '';
      final nonce = params['nonce'] ?? '';
      final opaque = params['opaque'] ?? '';
      final qop = params['qop'] ?? '';
      final cnonce = base64Encode(List<int>.generate(8, (_) => Random.secure().nextInt(256)));
      const nc = '00000001';

      final ha1 = _md5('${config.username}:$realm:${config.password}');
      final ha2 = _md5('GET:/ISAPI/System/deviceInfo');
      final response = _md5('$ha1:$nonce:$nc:$cnonce:$qop:$ha2');

      final auth = StringBuffer('Digest ');
      auth.write('username="${config.username}", ');
      auth.write('realm="$realm", ');
      auth.write('nonce="$nonce", ');
      auth.write('uri="/ISAPI/System/deviceInfo", ');
      auth.write('qop=$qop, ');
      auth.write('nc=$nc, ');
      auth.write('cnonce="$cnonce", ');
      auth.write('response="$response"');
      if (opaque.isNotEmpty) {
        auth.write(', opaque="$opaque"');
      }

      // 2nd request: with Digest auth.
      final req2 = http.Request('GET', uri);
      req2.headers['Authorization'] = auth.toString();
      final resp2 = await client.send(req2);
      final body2 = await resp2.stream.bytesToString();

      if (body2.toLowerCase().contains('device is locked')) {
        return 'Device is locked. Please wait and try again later.';
      }

      if (resp2.statusCode == 200) {
        AppLog.log('[ISAPI] Connection OK (auth success)');
        try {
          final nameMatch = RegExp(r'<deviceName>(.*?)</deviceName>').firstMatch(body2);
          if (nameMatch != null) {
            AppLog.log('[ISAPI] Device: ${nameMatch.group(1)}');
          }
        } catch (_) {}
        return null;
      }

      if (resp2.statusCode == 401) {
        AppLog.log('[ISAPI] Connection FAILED: 401 Unauthorized');
        return 'Authentication failed. Check username and password.';
      }

      return 'Unexpected response: HTTP ${resp2.statusCode}';
    } on SocketException catch (e) {
      AppLog.log('[ISAPI] Connection FAILED: $e');
      return 'Cannot reach camera at ${config.ip}. Check network connection.';
    } on HttpException catch (e) {
      AppLog.log('[ISAPI] Connection FAILED: $e');
      return e.message;
    } catch (e) {
      AppLog.log('[ISAPI] Connection FAILED: $e');
      return 'Connection error: $e';
    } finally {
      client.close();
    }
  }

  // ── VISCA command sender ────────────────────────────────────

  Future<String> _sendVisca(String viscaHex) async {
    final cleanHex = viscaHex.replaceAll(' ', '');
    _log('sendVisca: $cleanHex');
    final payload = jsonEncode({
      'version': 1,
      'cmd': 'visca_tran_jx',
      'cmd_src': 'visca',
      'attri': [
        {'key': 'ViscaProcess', 'val': cleanHex}
      ],
    });

    final resp = await _request(
      'POST',
      '/ISAPI/System/MovementMgr/channels/1/MovementParam?format=json',
      body: payload,
    );

    if (resp.statusCode != 200 && resp.statusCode != 500) {
      throw HttpException('ISAPI error ${resp.statusCode}: ${resp.body}');
    }

    try {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final result = json['result']?.toString() ?? 'unknown';
      _log('sendVisca result: $result');
      return result;
    } catch (_) {
      _log('sendVisca response: ${resp.statusCode}');
      return 'status_${resp.statusCode}';
    }
  }

  // ── Initialization ──────────────────────────────────────────

  Future<void> _initIfNeeded() async {
    if (_initialized) return;
    _initialized = true;
    _log('Initializing camera...');

    try {
      for (var i = 0; i < config.initCommands.length; i++) {
        final cmd = config.initCommands[i];
        if (!cmd.enabled) continue;
        // 间隔 0.5s 发送，避免设备处理不过来
        if (i > 0) await Future.delayed(const Duration(milliseconds: 500));
        switch (cmd.type) {
          case InitCommandType.visca:
            final result = await _sendVisca(cmd.content);
            _log('init ${cmd.name.isEmpty ? cmd.content : cmd.name} → $result');
          case InitCommandType.isapi:
            final resp = await _request(
              cmd.method.toUpperCase(),
              cmd.path,
              body: cmd.content,
              contentType: 'application/xml',
            );
            _log('init ${cmd.name.isEmpty ? cmd.path : cmd.name} → ${resp.statusCode}');
        }
      }
      _log('Camera initialized successfully');
    } catch (e) {
      _log('init failed: $e');
    }
  }

  // ── CameraProtocol ─────────────────────────────────────────

  @override
  Future<void> capture() async {
    await _initIfNeeded();
    _log('capture');
    final resp = await _request('GET', '/ISAPI/Streaming/channels/1/picture');
    if (resp.statusCode != 200) {
      throw HttpException('Capture error ${resp.statusCode}: ${resp.body}');
    }
  }

  @override
  Future<void> zoomIn() async {
    await _initIfNeeded();
    final cmd = _zoomInCmd ?? '8101040702ff';
    final result = await _sendVisca(cmd);
    _log('zoomIn → $result');
  }

  @override
  Future<void> zoomOut() async {
    await _initIfNeeded();
    final cmd = _zoomOutCmd ?? '8101040703ff';
    final result = await _sendVisca(cmd);
    _log('zoomOut → $result');
  }

  @override
  Future<void> zoomStop() async {
    final cmd = _zoomStopCmd ?? '8101040700ff';
    final result = await _sendVisca(cmd);
    _log('zoomStop → $result');
  }

  @override
  Future<void> focusAt(int x, int y) async {
    await _initIfNeeded();
    _log('focusAt: ($x, $y) — VISCA command not yet set');
  }

  @override
  void updateConfig(CameraConfig newConfig) {
    config = newConfig;
    _isLocked = false;
    _initialized = false;
    _log('Config updated: ${config.ip}, user=${config.username}, pwd=${config.password.isEmpty ? "(empty)" : "(set)"}');
  }

  @override
  void dispose() {
    _client.close();
  }
}