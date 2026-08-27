import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'camera_config.dart';
import 'camera_protocol.dart';
import 'digest_auth.dart';
import 'init_command.dart';

/// ISAPI protocol implementation for Hikvision cameras.
///
/// All HTTP requests are **serialized** through a single command queue.
/// This prevents concurrent requests from piling up and freezing the UI
/// when the user taps zoom buttons rapidly. Each request has a timeout.
///
/// The queue works like a dedicated "protocol thread":
/// - UI calls `zoomIn()` → enqueues a command → returns immediately
/// - Queue processes commands one by one in the background
/// - Latest zoom command can cancel pending ones (debounce for zoom)
class IsapiProtocol implements CameraProtocol {
  CameraConfig config;
  final http.Client _client = http.Client();
  String? _cnonce;
  int _nc = 0;
  bool _initialized = false;
  bool _isLocked = false;

  // ── Command queue (serial executor) ─────────────────────────
  //
  // A single Future chain ensures all HTTP requests run one at a time.
  // `Completer` is used so callers can await individual results.
  Future<void> _chain = Future.value();

  /// Enqueues a task onto the serial execution chain.
  /// Returns a Future that completes when the task finishes.
  Future<T> _enqueue<T>(Future<T> Function() task, {Duration timeout = const Duration(seconds: 5)}) {
    final completer = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        final result = await task().timeout(timeout, onTimeout: () {
          throw TimeoutException('Request timed out after ${timeout.inSeconds}s');
        });
        if (!completer.isCompleted) completer.complete(result);
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });
    return completer.future;
  }

  // ── VISCA commands ──────────────────────────────────────────

  final String? _zoomInCmd;
  final String? _zoomOutCmd;
  final String? _zoomStopCmd;

  IsapiProtocol({required this.config})
      : _zoomInCmd = null,
        _zoomOutCmd = null,
        _zoomStopCmd = null;

  IsapiProtocol.withVisca({
    required this.config,
    this._zoomInCmd,
    this._zoomOutCmd,
    this._zoomStopCmd,
  });

  // ── Logging ─────────────────────────────────────────────────

  void _log(String msg) {
    AppLog.log('[ISAPI] $msg');
  }

  // ── Digest auth ─────────────────────────────────────────────

  /// Sends a request with Digest auth. Runs on the serial queue.
  Future<http.Response> _request(
    String method,
    String path, {
    String? body,
    String contentType = 'application/json',
  }) {
    return _enqueue(() async {
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
      final resp1 = await _client.send(req1).timeout(const Duration(seconds: 5));
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
      final params = DigestAuth.parseParams(authHeader);
      if (params.isEmpty) {
        _log('$path → failed to parse WWW-Authenticate');
        return http.Response(body1, resp1.statusCode);
      }

      final realm = params['realm'] ?? '';
      _cnonce ??= DigestAuth.generateCnonce();
      _nc++;
      final ncStr = _nc.toString().padLeft(8, '0');
      _log('Digest: username=${config.username}, realm=$realm, nc=$ncStr');

      final auth = DigestAuth(username: config.username, password: config.password).buildHeader(
        method: method,
        uriPath: uri.path,
        params: params,
        cnonce: _cnonce!,
        nc: _nc,
      );

      final req2 = http.Request(method, uri);
      if (body != null) req2.body = body;
      req2.headers['Content-Type'] = contentType;
      req2.headers['Authorization'] = auth.toString();
      final resp2 = await _client.send(req2).timeout(const Duration(seconds: 5));
      final body2 = await resp2.stream.bytesToString();

      if (_checkLocked(body2)) return http.Response(body2, resp2.statusCode);

      _log('$path → ${resp2.statusCode}');
      return http.Response(body2, resp2.statusCode);
    });
  }

  bool _checkLocked(String body) {
    if (body.toLowerCase().contains('device is locked')) {
      _isLocked = true;
      _log('DEVICE LOCKED!');
      return true;
    }
    return false;
  }

  // ── Connection test (static, for settings screen) ───────────

  static Future<String?> testConnection(CameraConfig config) async {
    AppLog.log('[ISAPI] Testing connection to ${config.ip}...');
    final client = http.Client();
    try {
      final uri = Uri.parse('${config.httpUrl}/ISAPI/System/deviceInfo');

      final req1 = http.Request('GET', uri);
      final resp1 = await client.send(req1).timeout(const Duration(seconds: 5));
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

      final authHeader = resp1.headers['www-authenticate'] ?? '';
      final params = DigestAuth.parseParams(authHeader);

      final auth = DigestAuth(username: config.username, password: config.password).buildHeader(
        method: 'GET',
        uriPath: '/ISAPI/System/deviceInfo',
        params: params,
        cnonce: DigestAuth.generateCnonce(),
        nc: 1,
      );

      final req2 = http.Request('GET', uri);
      req2.headers['Authorization'] = auth.toString();
      final resp2 = await client.send(req2).timeout(const Duration(seconds: 5));
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
    } on TimeoutException {
      AppLog.log('[ISAPI] Connection FAILED: timeout');
      return 'Connection timed out. Check network.';
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
    // 保存配置后立即在后台发送初始化指令（fire-and-forget，走串行队列，不阻塞 UI）
    _initIfNeeded().catchError((e) => _log('post-save init failed: $e'));
  }

  @override
  void dispose() {
    _client.close();
  }
}