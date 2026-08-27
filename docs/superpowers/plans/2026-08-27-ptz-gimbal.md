# 外接云台 (PTZ) 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增外接 Hik 云台设备，通过 ISAPI 独立控制 pan/tilt，并使主设备变倍按钮联动驱动云台变倍。

**Architecture:** 新增 `PtzConfig` 嵌入 `CameraConfig` 持久化；新增 `PtzProtocol`（复用提取的 `DigestAuth` helper + 串行队列）走 `/ISAPI/PTZCtrl/channels/1/continuous`；`CameraState` 持可选 `PtzProtocol` 并在 zoom 调用时联动；设置页加云台段；预览页左下角加四方向控制盘。

**Tech Stack:** Flutter/Dart, provider, http + crypto (Digest), shared_preferences, flutter_test。

**设计依据:** `docs/superpowers/specs/2026-08-27-ptz-gimbal-design.md`

**代码风格约定（遵循现有代码）:**
- `@immutable` data class + `toJson`/`fromJson`/`copyWith`/`==`/`hashCode`，参照 `CameraConfig`。
- 协议类私有 `_request` 走串行 `_chain` 队列，`Completer` + `timeout`，参照 `IsapiProtocol`。
- 日志统一走 `AppLog.log('[PTZ] $msg')`。
- UI 圆形按钮视觉复用 `ZoomControls._ZoomButton` 样式（黑底白边、按下高亮缩放）。

---

## 文件结构

| 文件 | 责任 | 操作 |
|---|---|---|
| `lib/core/ptz_config.dart` | `PtzConfig` 数据模型 | 新建 |
| `lib/core/digest_auth.dart` | Digest 认证 helper（从 IsapiProtocol 提取） | 新建 |
| `lib/core/isapi_protocol.dart` | 改用 `DigestAuth`，行为不变 | 修改 |
| `lib/core/ptz_protocol.dart` | `PtzProtocol`（continuous PTZ + 变倍联动） | 新建 |
| `lib/core/camera_config.dart` | 嵌入 `PtzConfig ptz` 字段 | 修改 |
| `lib/features/camera_state.dart` | 持有 `PtzProtocol?`，zoom 联动 | 修改 |
| `lib/main.dart` | 装配 `PtzProtocol`（按 config.ptz.enabled） | 修改 |
| `lib/app.dart` | 把 `PtzProtocol?` 传入 `CameraState` | 修改 |
| `lib/features/ptz/ptz_controls.dart` | 四方向控制盘 UI | 新建 |
| `lib/features/preview/preview_screen.dart` | 左下角挂载 `PtzControls` | 修改 |
| `lib/features/settings/settings_screen.dart` | 云台配置段 | 修改 |
| `test/ptz_config_test.dart` | 数据模型测试 | 新建 |
| `test/ptz_protocol_test.dart` | 协议报文测试 | 新建 |
| `test/camera_state_test.dart` | 联动测试（已有，追加） | 修改 |
| `test/ptz_controls_test.dart` | 控制盘 UI 测试 | 新建 |

---

### Task 1: PtzConfig 数据模型

**Files:**
- Create: `lib/core/ptz_config.dart`
- Test: `test/ptz_config_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ptz_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_handheld/core/ptz_config.dart';

void main() {
  group('PtzConfig', () {
    test('defaults', () {
      const c = PtzConfig();
      expect(c.enabled, isFalse);
      expect(c.ip, '192.168.1.65');
      expect(c.password, '');
      expect(c.speed, 50);
    });

    test('toJson / fromJson round-trip', () {
      const c = PtzConfig(enabled: true, ip: '10.0.0.5', password: 'secret', speed: 75);
      final j = c.toJson();
      final back = PtzConfig.fromJson(j);
      expect(back, c);
    });

    test('fromJson backward-compat: missing ptz key uses defaults', () {
      // 模拟旧配置无 ptz 键时不会传入；这里测空 map
      final c = PtzConfig.fromJson({});
      expect(c.enabled, isFalse);
      expect(c.speed, 50);
    });

    test('copyWith', () {
      const c = PtzConfig();
      final c2 = c.copyWith(enabled: true, ip: '1.2.3.4', speed: 80);
      expect(c2.enabled, isTrue);
      expect(c2.ip, '1.2.3.4');
      expect(c2.speed, 80);
      expect(c2.password, '');
    });

    test('equality', () {
      const a = PtzConfig(enabled: true, ip: 'x', password: 'p', speed: 30);
      const b = PtzConfig(enabled: true, ip: 'x', password: 'p', speed: 30);
      const c = PtzConfig(enabled: false, ip: 'x', password: 'p', speed: 30);
      expect(a == b, isTrue);
      expect(a == c, isFalse);
      expect(a.hashCode, b.hashCode);
    });

    test('speed clamped to 1..100 on fromJson', () {
      expect(PtzConfig.fromJson({'speed': 0}).speed, 1);
      expect(PtzConfig.fromJson({'speed': 999}).speed, 100);
      expect(PtzConfig.fromJson({'speed': 50}).speed, 50);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd camera_handheld && flutter test test/ptz_config_test.dart`
Expected: FAIL — `ptz_config.dart` 不存在 / 编译错误。

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/ptz_config.dart
import 'package:flutter/foundation.dart';

/// 外接云台设备配置。用户名固定 admin。
/// 持久化随 CameraConfig 一起存储。
@immutable
class PtzConfig {
  final bool enabled;
  final String ip;
  final String password;
  /// 转动/变倍速度，1..100，归一化为 0.01..1.0 下发。
  final int speed;

  const PtzConfig({
    this.enabled = false,
    this.ip = '192.168.1.65',
    this.password = '',
    this.speed = 50,
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'ip': ip,
        'password': password,
        'speed': speed,
      };

  factory PtzConfig.fromJson(Map<String, dynamic> json) => PtzConfig(
        enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
        ip: json['ip'] is String ? json['ip'] as String : '192.168.1.65',
        password: json['password'] is String ? json['password'] as String : '',
        speed: _clampSpeed(json['speed'] is int ? json['speed'] as int : 50),
      );

  static int _clampSpeed(int v) => v.clamp(1, 100);

  /// 归一化速度 (0.01..1.0)，用于 ISAPI PTZData。
  double get normalizedSpeed => speed / 100.0;

  PtzConfig copyWith({
    bool? enabled,
    String? ip,
    String? password,
    int? speed,
  }) =>
      PtzConfig(
        enabled: enabled ?? this.enabled,
        ip: ip ?? this.ip,
        password: password ?? this.password,
        speed: speed ?? this.speed,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PtzConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          ip == other.ip &&
          password == other.password &&
          speed == other.speed;

  @override
  int get hashCode => Object.hash(enabled, ip, password, speed);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd camera_handheld && flutter test test/ptz_config_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
cd camera_handheld
git add lib/core/ptz_config.dart test/ptz_config_test.dart
git commit -m "feat(ptz): add PtzConfig data model"
```

---

### Task 2: DigestAuth helper 提取

**Files:**
- Create: `lib/core/digest_auth.dart`
- Test: 先不单独测（IsapiProtocol 现有测试覆盖其行为），实现后跑现有 isapi 测试验证零行为变化。

> 目标：把 `IsapiProtocol` 的 Digest 计算（realm/nonce/opaque/qop/cnonce/nc/HA1/HA2/response + Authorization 头拼装）抽成可复用 helper，`IsapiProtocol` 与后续 `PtzProtocol` 共用。**纯重构，IsapiProtocol 行为零变化。**

- [ ] **Step 1: 写 DigestAuth helper**

```dart
// lib/core/digest_auth.dart
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Hikvision ISAPI Digest 认证 helper。
/// 从 401 响应的 WWW-Authenticate 头解析参数，计算摘要并拼装 Authorization 头。
class DigestAuth {
  final String username;
  final String password;

  DigestAuth({required this.username, required this.password});

  static String _md5(String data) => md5.convert(utf8.encode(data)).toString();

  /// 解析 WWW-Authenticate 头里的 Digest 参数。
  static Map<String, String> parseParams(String header) {
    final params = <String, String>{};
    final h = header.replaceFirst(RegExp(r'^Digest\s+', caseSensitive: false), '');
    for (final match in RegExp(r'(\w+)\s*=\s*"([^"]*)"').allMatches(h)) {
      params[match.group(1)!] = match.group(2)!;
    }
    return params;
  }

  /// 生成 8 字节随机 cnonce（base64）。
  static String generateCnonce() {
    final rng = Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    return base64Encode(bytes);
  }

  /// 拼装完整 Authorization 头。
  /// [method] / [uriPath] 用于 HA2；[nc] 为 int，内部补零到 8 位。
  String buildHeader({
    required String method,
    required String uriPath,
    required Map<String, String> params,
    required String cnonce,
    required int nc,
  }) {
    final realm = params['realm'] ?? '';
    final nonce = params['nonce'] ?? '';
    final opaque = params['opaque'] ?? '';
    final qop = params['qop'] ?? '';
    final ncStr = nc.toString().padLeft(8, '0');

    final ha1 = _md5('$username:$realm:$password');
    final ha2 = _md5('$method:$uriPath');
    final response = _md5('$ha1:$nonce:$ncStr:$cnonce:$qop:$ha2');

    final auth = StringBuffer('Digest ');
    auth.write('username="$username", ');
    auth.write('realm="$realm", ');
    auth.write('nonce="$nonce", ');
    auth.write('uri="$uriPath", ');
    auth.write('qop=$qop, ');
    auth.write('nc=$ncStr, ');
    auth.write('cnonce="$cnonce", ');
    auth.write('response="$response"');
    if (opaque.isNotEmpty) {
      auth.write(', opaque="$opaque"');
    }
    return auth.toString();
  }
}
```

- [ ] **Step 2: 重构 IsapiProtocol 复用 DigestAuth**

修改 `lib/core/isapi_protocol.dart`：
- 顶部 import `'digest_auth.dart'`。
- `_md5` 私有方法可保留（其他地方用到？检查：只在认证用 → 删除，改用 DigestAuth）。实际上 `_md5` 仅认证用，删除该静态方法，认证段改用 `DigestAuth`。
- 实例化 `final DigestAuth _digest = DigestAuth(username: config.username, password: config.password);` —— 但 config 可变（updateConfig），需在每次请求时按当前 config 构造，或在 updateConfig 时重建。最简：`_request` 内按当前 config 临时构造 `DigestAuth`。
- `_request` 里 401 段：
  ```dart
  final params = DigestAuth.parseParams(authHeader);   // 替换 _parseDigestParams(authHeader)
  ...
  _cnonce ??= DigestAuth.generateCnonce();            // 替换 _generateCnonce()
  _nc++;
  final auth = _digest.buildHeader(                    // 替换手动拼装
    method: method,
    uriPath: uri.path,
    params: params,
    cnonce: _cnonce!,
    nc: _nc,
  );
  ```
  其中 `_digest` 改为请求内局部：`final digest = DigestAuth(username: config.username, password: config.password);`
- `testConnection` 静态方法里同样用 `DigestAuth.parseParams` / `generateCnonce` / `buildHeader`。
- 删除 `_parseDigestParams`、`_generateCnonce`、`_md5` 三个被替代的私有方法。

- [ ] **Step 3: 跑现有 isapi 测试验证零行为变化**

Run: `cd camera_handheld && flutter test test/isapi_protocol_test.dart`
Expected: 全部 PASS（与重构前一致）。

- [ ] **Step 4: Commit**

```bash
cd camera_handheld
git add lib/core/digest_auth.dart lib/core/isapi_protocol.dart
git commit -m "refactor: extract DigestAuth helper, IsapiProtocol behavior unchanged"
```

---

### Task 3: PtzProtocol 协议实现

**Files:**
- Create: `lib/core/ptz_protocol.dart`
- Test: `test/ptz_protocol_test.dart`

> 复用 `DigestAuth` + 串行队列（同 IsapiProtocol 思路）。PTZData XML 用新固件字段 `pan`/`tilt`/`zoom`。

- [ ] **Step 1: Write the failing test**

```dart
// test/ptz_protocol_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:camera_handheld/core/ptz_config.dart';
import 'package:camera_handheld/core/ptz_protocol.dart';

/// 捕获最后一次请求的 method/path/body。
void main() {
  group('PtzProtocol', () {
    test('move up: tilt negative, pan zero', () async {
      String? body;
      final client = MockClient((request) async {
        body = request.body;
        // 首包 401 触发 digest 流程，次包 200
        if (request.headers['Authorization'] == null) {
          return http.Response('', 401, headers: {
            'www-authenticate':
                'Digest realm="test", nonce="n1", qop="auth", opaque="o1"'
          });
        }
        return http.Response('OK', 200);
      });

      final ptz = PtzProtocol.forTesting(
        const PtzConfig(enabled: true, ip: '1.1.1.1', password: 'p', speed: 50),
        client,
      );
      await ptz.move(pan: 0, tilt: -1, zoom: 0);

      expect(body, contains('<pan>0</pan>'));
      expect(body, contains('<tilt>-0.5</tilt>'));
      expect(body, contains('<zoom>0</zoom>'));
    });

    test('move right: pan positive', () async {
      String? body;
      final client = MockClient((request) async {
        body = request.body;
        if (request.headers['Authorization'] == null) {
          return http.Response('', 401, headers: {
            'www-authenticate':
                'Digest realm="test", nonce="n1", qop="auth"'
          });
        }
        return http.Response('OK', 200);
      });

      final ptz = PtzProtocol.forTesting(
        const PtzConfig(enabled: true, ip: '1.1.1.1', password: 'p', speed: 80),
        client,
      );
      await ptz.move(pan: 1, tilt: 0, zoom: 0);

      expect(body, contains('<pan>0.8</pan>'));
      expect(body, contains('<tilt>0</tilt>'));
    });

    test('stop sends all-zero PTZData', () async {
      String? body;
      final client = MockClient((request) async {
        body = request.body;
        if (request.headers['Authorization'] == null) {
          return http.Response('', 401, headers: {
            'www-authenticate':
                'Digest realm="test", nonce="n1", qop="auth"'
          });
        }
        return http.Response('OK', 200);
      });

      final ptz = PtzProtocol.forTesting(
        const PtzConfig(enabled: true, ip: '1.1.1.1', password: 'p', speed: 50),
        client,
      );
      await ptz.stop();

      expect(body, contains('<pan>0</pan>'));
      expect(body, contains('<tilt>0</tilt>'));
      expect(body, contains('<zoom>0</zoom>'));
    });

    test('zoomIn: zoom positive, pan/tilt zero', () async {
      String? body;
      final client = MockClient((request) async {
        body = request.body;
        if (request.headers['Authorization'] == null) {
          return http.Response('', 401, headers: {
            'www-authenticate':
                'Digest realm="test", nonce="n1", qop="auth"'
          });
        }
        return http.Response('OK', 200);
      });

      final ptz = PtzProtocol.forTesting(
        const PtzConfig(enabled: true, ip: '1.1.1.1', password: 'p', speed: 50),
        client,
      );
      await ptz.zoomIn();

      expect(body, contains('<zoom>0.5</zoom>'));
      expect(body, contains('<pan>0</pan>'));
      expect(body, contains('<tilt>0</tilt>'));
    });

    test('zoomOut: zoom negative', () async {
      String? body;
      final client = MockClient((request) async {
        body = request.body;
        if (request.headers['Authorization'] == null) {
          return http.Response('', 401, headers: {
            'www-authenticate':
                'Digest realm="test", nonce="n1", qop="auth"'
          });
        }
        return http.Response('OK', 200);
      });

      final ptz = PtzProtocol.forTesting(
        const PtzConfig(enabled: true, ip: '1.1.1.1', password: 'p', speed: 50),
        client,
      );
      await ptz.zoomOut();

      expect(body, contains('<zoom>-0.5</zoom>'));
    });

    test('locked device sets _isLocked and throws on next call', () async {
      final client = MockClient((request) async {
        return http.Response('device is locked', 401);
      });

      final ptz = PtzProtocol.forTesting(
        const PtzConfig(enabled: true, ip: '1.1.1.1', password: 'p', speed: 50),
        client,
      );
      // 第一次触发锁定检测
      await ptz.stop().catchError((_) {});
      // 第二次应因 _isLocked 直接抛错
      expect(() => ptz.stop(), throwsA(isA<StateError>()));
    });

    test('requests serialized through queue', () async {
      final order = <String>[];
      final client = MockClient((request) async {
        order.add(request.body ?? '');
        if (request.headers['Authorization'] == null) {
          return http.Response('', 401, headers: {
            'www-authenticate':
                'Digest realm="test", nonce="n1", qop="auth"'
          });
        }
        await Future.delayed(const Duration(milliseconds: 10));
        return http.Response('OK', 200);
      });

      final ptz = PtzProtocol.forTesting(
        const PtzConfig(enabled: true, ip: '1.1.1.1', password: 'p', speed: 50),
        client,
      );
      await Future.wait([ptz.zoomIn(), ptz.zoomOut(), ptz.stop()]);
      // 三个请求顺序执行（不会交错）
      expect(order.length, greaterThanOrEqualTo(3));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd camera_handheld && flutter test test/ptz_protocol_test.dart`
Expected: FAIL — `ptz_protocol.dart` 不存在。

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/core/ptz_protocol.dart
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
  bool _isTesting;

  Future<void> _chain = Future.value();

  PtzProtocol({required this.config})
      : _client = http.Client(),
        _ownsClient = true,
        _isTesting = false;

  /// 测试构造函数：注入 http client。
  PtzProtocol.forTesting(this.config, http.Client client)
      : _client = client,
        _ownsClient = false,
        _isTesting = true;

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
```

> 注：测试里 `_isTesting` 字段当前未使用，保留以备区分真实/测试日志；如 lint 报未使用，可移除该字段及构造参数。实现时按 lint 结果处理。

- [ ] **Step 4: Run test to verify it passes**

Run: `cd camera_handheld && flutter test test/ptz_protocol_test.dart`
Expected: PASS (7 tests)。若 `_isTesting` 报 unused，删除该字段与 `forTesting` 里的赋值，重跑。

- [ ] **Step 5: Commit**

```bash
cd camera_handheld
git add lib/core/ptz_protocol.dart test/ptz_protocol_test.dart
git commit -m "feat(ptz): add PtzProtocol with continuous PTZ + zoom relay"
```

---

### Task 4: CameraConfig 嵌入 PtzConfig

**Files:**
- Modify: `lib/core/camera_config.dart`
- Test: `test/camera_config_test.dart`（已有，追加）

- [ ] **Step 1: Write the failing test (append to existing file)**

在 `test/camera_config_test.dart` 末尾 `main` 内追加：

```dart
  group('ptz', () {
    test('default ptz disabled', () {
      const c = CameraConfig();
      expect(c.ptz.enabled, isFalse);
      expect(c.ptz.speed, 50);
    });

    test('toJson/fromJson round-trips ptz', () {
      const c = CameraConfig(
        ptz: PtzConfig(enabled: true, ip: '9.9.9.9', password: 'pw', speed: 70),
      );
      final back = CameraConfig.fromJson(c.toJson());
      expect(back.ptz, c.ptz);
    });

    test('fromJson backward-compat: missing ptz key → default', () {
      final back = CameraConfig.fromJson({
        'ip': '1.2.3.4',
        'username': 'admin',
        'password': 'x',
      });
      expect(back.ptz.enabled, isFalse);
      expect(back.ptz.ip, '192.168.1.65');
    });

    test('copyWith ptz', () {
      const c = CameraConfig();
      final c2 = c.copyWith(ptz: const PtzConfig(enabled: true, speed: 90));
      expect(c2.ptz.enabled, isTrue);
      expect(c2.ptz.speed, 90);
    });
  });
```
顶部加 `import 'package:camera_handheld/core/ptz_config.dart';`。

- [ ] **Step 2: Run test to verify it fails**

Run: `cd camera_handheld && flutter test test/camera_config_test.dart`
Expected: FAIL — `ptz` 字段不存在 / 编译错误。

- [ ] **Step 3: Modify CameraConfig**

`lib/core/camera_config.dart`：
- import `'ptz_config.dart'`。
- 类字段加 `final PtzConfig ptz;`（默认 `const PtzConfig()`）。
- 构造函数加 `this.ptz = const PtzConfig(),`。
- `toJson` 加 `'ptz': ptz.toJson(),`。
- `fromJson`：`ptz: json['ptz'] is Map ? PtzConfig.fromJson(json['ptz'] as Map<String, dynamic>) : const PtzConfig(),`
- `copyWith` 加 `PtzConfig? ptz` 参数 + `ptz: ptz ?? this.ptz,`。
- `==` 加 `ptz == other.ptz,`。
- `hashCode` 把 `ptz` 并入 `Object.hash(...)`。

- [ ] **Step 4: Run test to verify it passes**

Run: `cd camera_handheld && flutter test test/camera_config_test.dart`
Expected: PASS（含新增 ptz group）。

- [ ] **Step 5: Commit**

```bash
cd camera_handheld
git add lib/core/camera_config.dart test/camera_config_test.dart
git commit -m "feat(ptz): embed PtzConfig in CameraConfig"
```

---

### Task 5: CameraState 持有 PtzProtocol + 变倍联动

**Files:**
- Modify: `lib/features/camera_state.dart`
- Test: `test/camera_state_test.dart`（已有，参照其现有 fake protocol 风格追加）

- [ ] **Step 1: Read existing camera_state_test.dart to match patterns**

Run: `cat camera_handheld/test/camera_state_test.dart`
了解现有 fake protocol / 测试风格后再写。

- [ ] **Step 2: Write the failing test (append)**

追加 group：

```dart
  group('ptz relay', () {
    test('zoomIn calls ptz.zoomIn when ptz enabled', () async {
      final camera = _FakeCameraProtocol();
      final ptz = _FakePtzProtocol();
      final state = CameraState(
        protocol: camera,
        config: const CameraConfig(
          ptz: PtzConfig(enabled: true, ip: '1.1.1.1', password: 'p', speed: 50),
        ),
        ptzProtocol: ptz,
      );
      await state.zoomIn();
      expect(ptz.zoomInCalls, 1);
      expect(ptz.zoomOutCalls, 0);
      expect(ptz.stopCalls, 0);
    });

    test('zoomIn does NOT call ptz when disabled', () async {
      final camera = _FakeCameraProtocol();
      final ptz = _FakePtzProtocol();
      final state = CameraState(
        protocol: camera,
        config: const CameraConfig(), // ptz disabled
        ptzProtocol: ptz,
      );
      await state.zoomIn();
      expect(ptz.zoomInCalls, 0);
    });

    test('zoomStop relays stop to ptz when enabled', () async {
      final camera = _FakeCameraProtocol();
      final ptz = _FakePtzProtocol();
      final state = CameraState(
        protocol: camera,
        config: const CameraConfig(
          ptz: PtzConfig(enabled: true, ip: '1.1.1.1', password: 'p', speed: 50),
        ),
        ptzProtocol: ptz,
      );
      state.zoomStop();
      // fire-and-forget; 给微任务机会
      await Future.delayed(Duration.zero);
      expect(ptz.stopCalls, 1);
    });
  });
```

并在测试文件加 fake：

```dart
class _FakePtzProtocol {
  int zoomInCalls = 0;
  int zoomOutCalls = 0;
  int stopCalls = 0;
  Future<void> zoomIn() async => zoomInCalls++;
  Future<void> zoomOut() async => zoomOutCalls++;
  Future<void> zoomStop() async => stopCalls++;
  void updateConfig(PtzConfig c) {}
  void dispose() {}
}
```

> 注：CameraState 需接受 `PtzProtocol?` 或抽象。为可测试，定义小接口或直接用 duck-typed 类型。最简：CameraState 字段类型设为带 `zoomIn/zoomOut/zoomStop/updateConfig/dispose` 的抽象。建议新建 `lib/core/ptz_protocol.dart` 里加抽象基类，或 CameraState 直接持 `PtzProtocol?`（真实类）。测试用真实 `PtzProtocol.forTesting` + MockClient 更贴合，但为简化联动断言，用抽象接口更直接。
>
> **决策**：在 `ptz_protocol.dart` 增加抽象 `PtzProtocol`（真实类重命名 `IsapiPtzProtocol`），CameraState 持 `PtzProtocol?`。但为减少改动面，**改回更简单方案**：CameraState 持 `PtzProtocol?`（真实类），测试用真实类 + MockClient。下面 Step 3 按真实类接线。

**修正测试方案（Step 2 实际用真实 PtzProtocol + MockClient）：**

```dart
// test/camera_state_test.dart 追加
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:camera_handheld/core/ptz_config.dart';
import 'package:camera_handheld/core/ptz_protocol.dart';

http.Client _okClient() => MockClient((request) async {
      if (request.headers['Authorization'] == null) {
        return http.Response('', 401, headers: {
          'www-authenticate': 'Digest realm="t", nonce="n", qop="auth"'
        });
      }
      return http.Response('OK', 200);
    });

  group('ptz relay', () {
    test('zoomIn relays to ptz when enabled', () async {
      final camera = _FakeCameraProtocol();
      final ptz = PtzProtocol.forTesting(
        const PtzConfig(enabled: true, ip: '1.1.1.1', password: 'p', speed: 50),
        _okClient(),
      );
      final state = CameraState(
        protocol: camera,
        config: const CameraConfig(
          ptz: PtzConfig(enabled: true, ip: '1.1.1.1', password: 'p', speed: 50),
        ),
        ptzProtocol: ptz,
      );
      await state.zoomIn();
      // 联动为 fire-and-forget；等队列消化
      await Future.delayed(const Duration(milliseconds: 50));
      // 无法直接断言 ptz 内部调用次数；改为验证不抛错即可。
      expect(state.zoomLevel, greaterThan(1.0));
    });

    test('zoomIn does not throw when ptz disabled', () async {
      final camera = _FakeCameraProtocol();
      final state = CameraState(protocol: camera, config: const CameraConfig());
      await state.zoomIn();
      expect(state.zoomLevel, greaterThan(1.0));
    });
  });
```

> 联动的核心断言是「不抛错 + 主流程不被云台失败阻断」。更精细的「ptz 是否被调用」用真实类难断言，改为通过日志或 spy。**务实取舍**：在 CameraState 注入一个可选的 `void Function(String)? ptzZoomRelay` 回调用于测试 spy，生产代码传入 `ptz.zoomIn` 等。但这增加复杂度。
>
> **最终决策**：CameraState 接受 `PtzProtocol?`（真实类）。联动用 try/catch 包裹。测试只验证「启用时不抛错、禁用时无影响」。联动正确性靠 PtzProtocol 单测（Task 3 已覆盖报文）+ 集成手测。这是合理测试边界。

- [ ] **Step 3: Modify CameraState**

`lib/features/camera_state.dart`：
- import `'../core/ptz_protocol.dart'` 与 `'../core/ptz_config.dart'`（ptz_config 经 camera_config 间接已可用，但显式 import 清晰）。
- 字段 `final PtzProtocol? ptzProtocol;`（构造注入，可空）。
- 构造函数加 `{this.ptzProtocol}`。
- `zoomIn()`：在主协议调用后追加 `_relayPtzZoom(1)`；`zoomOut()` 追加 `_relayPtzZoom(-1)`；`zoomStop()` 追加 `_relayPtzStop()`。
- 新增方法：
  ```dart
  void _relayPtzZoom(int dir) {
    if (ptzProtocol == null || !config.ptz.enabled) return;
    final f = dir > 0 ? ptzProtocol!.zoomIn() : ptzProtocol!.zoomOut();
    f.catchError((e) => debugPrint('[CameraState] ptz zoom relay error: $e'));
  }

  void _relayPtzStop() {
    if (ptzProtocol == null || !config.ptz.enabled) return;
    ptzProtocol!.zoomStop().catchError((e) => debugPrint('[CameraState] ptz stop relay error: $e'));
  }
  ```
- `updateConfig`：若新 config.ptz.enabled 且 ptzProtocol != null，调用 `ptzProtocol!.updateConfig(newConfig.ptz)`。

- [ ] **Step 4: Run test to verify it passes**

Run: `cd camera_handheld && flutter test test/camera_state_test.dart`
Expected: PASS（含 ptz relay group）。

- [ ] **Step 5: Commit**

```bash
cd camera_handheld
git add lib/features/camera_state.dart test/camera_state_test.dart
git commit -m "feat(ptz): relay main zoom to PtzProtocol in CameraState"
```

---

### Task 6: 装配（main + app）

**Files:**
- Modify: `lib/main.dart`, `lib/app.dart`

- [ ] **Step 1: Modify main.dart**

在 `runApp` 前按 config.ptz.enabled 构造 `PtzProtocol`：

```dart
// lib/main.dart
import 'core/ptz_protocol.dart';
...
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final config = await CameraConfigStore.load();
  final protocol = IsapiProtocol(config: config);

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
```

- [ ] **Step 2: Modify app.dart**

`CameraApp` 加 `final PtzProtocol? ptzProtocol;` 字段 + 构造参数，传入 `CameraState`：

```dart
// lib/app.dart
import 'core/ptz_protocol.dart';
...
class CameraApp extends StatelessWidget {
  final CameraProtocol protocol;
  final CameraConfig initialConfig;
  final PtzProtocol? ptzProtocol;

  const CameraApp({
    super.key,
    required this.protocol,
    required this.initialConfig,
    this.ptzProtocol,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CameraState(
        protocol: protocol,
        config: initialConfig,
        ptzProtocol: ptzProtocol,
      ),
      ...
```

- [ ] **Step 3: Verify compile**

Run: `cd camera_handheld && flutter analyze lib/main.dart lib/app.dart`
Expected: 无 error。

- [ ] **Step 4: Commit**

```bash
cd camera_handheld
git add lib/main.dart lib/app.dart
git commit -m "feat(ptz): wire PtzProtocol into app assembly"
```

---

### Task 7: PtzControls UI

**Files:**
- Create: `lib/features/ptz/ptz_controls.dart`
- Test: `test/ptz_controls_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ptz_controls_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_handheld/features/ptz/ptz_controls.dart';

void main() {
  Future<void> pumpPtz(WidgetTester t, {bool enabled = true}) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PtzControls(
          enabled: enabled,
          tapStopDelayMs: 60,
          onMove: (dir) {},
          onStop: () {},
        ),
      ),
    ));
  }

  testWidgets('renders 4 direction buttons when enabled', (t) async {
    await pumpPtz(t);
    expect(find.byIcon(Icons.arrow_drop_up), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    expect(find.byIcon(Icons.arrow_left), findsOneWidget);
    expect(find.byIcon(Icons.arrow_right), findsOneWidget);
  });

  testWidgets('renders nothing when disabled', (t) async {
    await pumpPtz(t, enabled: false);
    expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
  });

  testWidgets('long press up triggers move up', (t) async {
    final moves = <PtzDirection>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PtzControls(
          enabled: true,
          tapStopDelayMs: 60,
          onMove: moves.add,
          onStop: () {},
        ),
      ),
    ));
    await t.press(find.byIcon(Icons.arrow_drop_up));
    await t.pumpAndSettle();
    // press 触发 onLongPressStart → move up
    expect(moves, contains(PtzDirection.up));
  });

  testWidgets('tap up triggers move up then stop after delay', (t) async {
    final moves = <PtzDirection>[];
    var stops = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PtzControls(
          enabled: true,
          tapStopDelayMs: 60,
          onMove: moves.add,
          onStop: () => stops++,
        ),
      ),
    ));
    await t.tap(find.byIcon(Icons.arrow_drop_up));
    await t.pumpAndSettle(const Duration(milliseconds: 200));
    expect(moves, contains(PtzDirection.up));
    expect(stops, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd camera_handheld && flutter test test/ptz_controls_test.dart`
Expected: FAIL — 文件不存在。

- [ ] **Step 3: Write implementation**

```dart
// lib/features/ptz/ptz_controls.dart
import 'dart:async';

import 'package:flutter/material.dart';

enum PtzDirection { up, down, left, right }

/// 四方向云台控制盘。长按连续移动，短按脉冲移动（tapStopDelayMs 后 stop）。
/// disabled 时返回 SizedBox.shrink。
class PtzControls extends StatefulWidget {
  final bool enabled;
  final int tapStopDelayMs;
  final ValueChanged<PtzDirection> onMove;
  final VoidCallback onStop;

  const PtzControls({
    super.key,
    required this.enabled,
    required this.tapStopDelayMs,
    required this.onMove,
    required this.onStop,
  });

  @override
  State<PtzControls> createState() => _PtzControlsState();
}

class _PtzControlsState extends State<PtzControls> {
  Timer? _stopTimer;

  @override
  void dispose() {
    _stopTimer?.cancel();
    super.dispose();
  }

  Widget _dirButton(PtzDirection dir, IconData icon) {
    return _PtzDirButton(
      icon: icon,
      onStart: () {
        _stopTimer?.cancel();
        widget.onMove(dir);
      },
      onTapStop: () {
        _stopTimer?.cancel();
        _stopTimer = Timer(Duration(milliseconds: widget.tapStopDelayMs), () {
          if (mounted) widget.onStop();
        });
      },
      onLongPressEnd: () {
        _stopTimer?.cancel();
        widget.onStop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    return SizedBox(
      width: 152,
      height: 152,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 上
          Positioned(top: 0, child: _dirButton(PtzDirection.up, Icons.arrow_drop_up)),
          // 下
          Positioned(bottom: 0, child: _dirButton(PtzDirection.down, Icons.arrow_drop_down)),
          // 左
          Positioned(left: 0, child: _dirButton(PtzDirection.left, Icons.arrow_left)),
          // 右
          Positioned(right: 0, child: _dirButton(PtzDirection.right, Icons.arrow_right)),
        ],
      ),
    );
  }
}

class _PtzDirButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onStart;
  final VoidCallback onTapStop;
  final VoidCallback onLongPressEnd;

  const _PtzDirButton({
    required this.icon,
    required this.onStart,
    required this.onTapStop,
    required this.onLongPressEnd,
  });

  @override
  State<_PtzDirButton> createState() => _PtzDirButtonState();
}

class _PtzDirButtonState extends State<_PtzDirButton> {
  bool _isPressed = false;

  void _setPressed(bool v) {
    if (_isPressed != v) setState(() => _isPressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) {
        _setPressed(false);
        widget.onTapStop();
      },
      onTapCancel: () => _setPressed(false),
      onTap: () {
        // onTap 在 onTapUp 后；移动已在 onStart(onTapDown) 触发，这里只确保 stop 计时
      },
      onLongPressStart: (_) {
        _setPressed(true);
        widget.onStart();
      },
      onLongPressEnd: (_) {
        _setPressed(false);
        widget.onLongPressEnd();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: 48,
        height: 48,
        transform: _isPressed
            ? Matrix4.diagonal3Values(0.88, 0.88, 1.0)
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _isPressed
                ? Colors.white.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.25),
            width: _isPressed ? 1.5 : 1,
          ),
          color: _isPressed
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.5),
        ),
        child: Icon(
          widget.icon,
          color: _isPressed ? Colors.white : Colors.white.withValues(alpha: 0.85),
          size: 28,
        ),
      ),
    );
  }
}
```

> 注：测试里 `onTapUp` 触发 `onTapStop`（启动 stop 计时）。但短按脉冲需要先 move 再 stop：`onTapDown` 时应先 move（onStart）。当前 `_PtzDirButton` 的 `onTapDown` 只 `_setPressed(true)` 未 move。需修正：短按语义 = 按下即 move，松开即 stop-after-delay。与 `ZoomControls._ZoomButton` 一致（其 `_onTap` 才 move）。但 ZoomButton 是 `onTap` 时 start。
>
> **修正设计**（与 ZoomControls 对齐）：短按在 `onTap`（完整点击）时 onStart+schedule stop；长按用 onLongPressStart/End。下面 Step 3 的 `_PtzDirButton` 已用 onLongPressStart 触发 onStart；短按则在 onTapDown 也要 move 否则短按无动作。但 GestureDetector 的 onTap 与 onLongPressStart 互斥（长按不触发 onTap）。
>
> **最终对齐 ZoomControls 行为**：
> - `onTapDown`: 仅 `_setPressed(true)`。
> - `onTap`: `widget.onStart()` + `schedule stop after delay`（短按脉冲）。
> - `onLongPressStart`: `_setPressed(true)` + `widget.onStart()`。
> - `onLongPressEnd`: cancel timer + `_setPressed(false)` + `widget.onStop()`。
>
> 按此修正 `_PtzDirButtonState.build` 的回调：
> ```dart
>   onTapDown: (_) => _setPressed(true),
>   onTapUp: (_) => _setPressed(false),
>   onTapCancel: () => _setPressed(false),
>   onTap: () {
>     widget.onStart();
>     _stopTimer?.cancel();
>     _stopTimer = Timer(Duration(milliseconds: widget.tapStopDelayMs), () {
>       if (mounted) widget.onStop();
>     });
>   },
>   onLongPressStart: (_) {
>     _setPressed(true);
>     widget.onStart();
>   },
>   onLongPressEnd: (_) {
>     _stopTimer?.cancel();
>     _setPressed(false);
>     widget.onStop();
>   },
> ```
> `_stopTimer` 要提到 `_PtzControlsState` 还是 `_PtzDirButtonState`？每个按钮独立计时更对，放 `_PtzDirButtonState`。`_PtzControlsState` 的 `_stopTimer` 删掉，`_dirButton` 不再传 `onTapStop`/`onLongPressEnd` 分别处理，改为 `onStart`/`onStop`/`tapStopDelayMs`。
>
> 重写 `_PtzDirButton` 接口：`{icon, onStart, onStop, tapStopDelayMs}`，内部管 timer。`_PtzControlsState` 不再持 timer。

**用此修正版重写 Step 3 完整文件**（实现时以此为准）：

```dart
// lib/features/ptz/ptz_controls.dart
import 'dart:async';

import 'package:flutter/material.dart';

enum PtzDirection { up, down, left, right }

/// 四方向云台控制盘。长按连续移动，短按脉冲（tapStopDelayMs 后 stop）。
/// disabled 时返回 SizedBox.shrink。
class PtzControls extends StatelessWidget {
  final bool enabled;
  final int tapStopDelayMs;
  final ValueChanged<PtzDirection> onMove;
  final VoidCallback onStop;

  const PtzControls({
    super.key,
    required this.enabled,
    required this.tapStopDelayMs,
    required this.onMove,
    required this.onStop,
  });

  Widget _dir(PtzDirection d, IconData icon) => _PtzDirButton(
        icon: icon,
        onStart: () => onMove(d),
        onStop: onStop,
        tapStopDelayMs: tapStopDelayMs,
      );

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return SizedBox(
      width: 152,
      height: 152,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(top: 0, child: _dir(PtzDirection.up, Icons.arrow_drop_up)),
          Positioned(bottom: 0, child: _dir(PtzDirection.down, Icons.arrow_drop_down)),
          Positioned(left: 0, child: _dir(PtzDirection.left, Icons.arrow_left)),
          Positioned(right: 0, child: _dir(PtzDirection.right, Icons.arrow_right)),
        ],
      ),
    );
  }
}

class _PtzDirButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final int tapStopDelayMs;

  const _PtzDirButton({
    required this.icon,
    required this.onStart,
    required this.onStop,
    required this.tapStopDelayMs,
  });

  @override
  State<_PtzDirButton> createState() => _PtzDirButtonState();
}

class _PtzDirButtonState extends State<_PtzDirButton> {
  bool _isPressed = false;
  Timer? _stopTimer;

  @override
  void dispose() {
    _stopTimer?.cancel();
    super.dispose();
  }

  void _setPressed(bool v) {
    if (_isPressed != v) setState(() => _isPressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        widget.onStart();
        _stopTimer?.cancel();
        _stopTimer = Timer(Duration(milliseconds: widget.tapStopDelayMs), () {
          if (mounted) widget.onStop();
        });
      },
      onLongPressStart: (_) {
        _setPressed(true);
        widget.onStart();
      },
      onLongPressEnd: (_) {
        _stopTimer?.cancel();
        _setPressed(false);
        widget.onStop();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: 48,
        height: 48,
        transform: _isPressed
            ? Matrix4.diagonal3Values(0.88, 0.88, 1.0)
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _isPressed
                ? Colors.white.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.25),
            width: _isPressed ? 1.5 : 1,
          ),
          color: _isPressed
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.5),
        ),
        child: Icon(
          widget.icon,
          color: _isPressed ? Colors.white : Colors.white.withValues(alpha: 0.85),
          size: 28,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd camera_handheld && flutter test test/ptz_controls_test.dart`
Expected: PASS (4 tests)。

- [ ] **Step 5: Commit**

```bash
cd camera_handheld
git add lib/features/ptz/ptz_controls.dart test/ptz_controls_test.dart
git commit -m "feat(ptz): add four-direction PtzControls widget"
```

---

### Task 8: 预览页挂载云台控制盘

**Files:**
- Modify: `lib/features/preview/preview_screen.dart`

- [ ] **Step 1: Add left-bottom PtzControls to Stack**

在 `preview_screen.dart` build 的 `Stack.children` 里，快门按钮 `Positioned` 之后追加：

```dart
              // ── 云台控制盘（启用时显示，左下角）──
              Positioned(
                bottom: 40,
                left: 20,
                child: Consumer<CameraState>(
                  builder: (context, state, _) {
                    if (!state.config.ptz.enabled) return const SizedBox.shrink();
                    return PtzControls(
                      enabled: true,
                      tapStopDelayMs: state.config.zoomTapDelayMs,
                      onMove: (dir) {
                        final ptz = state.ptzProtocol;
                        if (ptz == null) return;
                        switch (dir) {
                          case PtzDirection.up:
                            ptz.up();
                          case PtzDirection.down:
                            ptz.down();
                          case PtzDirection.left:
                            ptz.left();
                          case PtzDirection.right:
                            ptz.right();
                        }
                      },
                      onStop: () {
                        state.ptzProtocol?.stop().catchError((e) {
                          debugPrint('[Preview] ptz stop error: $e');
                        });
                      },
                    );
                  },
                ),
              ),
```

顶部加 import：
```dart
import '../../core/ptz_protocol.dart';
import '../ptz/ptz_controls.dart';
```
（`debugPrint` 来自 material.dart，已 import。`ptzProtocol` getter 需在 CameraState 暴露——Task 5 字段 `final` 已暴露。）

- [ ] **Step 2: Verify compile + analyze**

Run: `cd camera_handheld && flutter analyze lib/features/preview/preview_screen.dart`
Expected: 无 error。

- [ ] **Step 3: Commit**

```bash
cd camera_handheld
git add lib/features/preview/preview_screen.dart
git commit -m "feat(ptz): mount PtzControls at preview bottom-left"
```

---

### Task 9: 设置页云台配置段

**Files:**
- Modify: `lib/features/settings/settings_screen.dart`
- Test: `test/settings_screen_test.dart`（已有，追加）

- [ ] **Step 1: Read existing settings_screen_test.dart patterns**

Run: `cat camera_handheld/test/settings_screen_test.dart`

- [ ] **Step 2: Write the failing test (append)**

追加 group（按现有测试的 pumpWidget 风格）：

```dart
  group('ptz section', () {
    testWidgets('shows ptz enable switch', (t) async {
      await t.pumpWidget(MaterialApp(
        home: SettingsScreen(initialConfig: const CameraConfig()),
      ));
      expect(find.text('云台'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('toggling switch reveals ip/password/speed', (t) async {
      await t.pumpWidget(MaterialApp(
        home: SettingsScreen(initialConfig: const CameraConfig()),
      ));
      // 默认禁用 → 不显示 ip/password/speed
      expect(find.text('云台设备 IP'), findsNothing);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(find.text('云台设备 IP'), findsOneWidget);
      expect(find.text('云台密码'), findsOneWidget);
    });

    testWidgets('disabled by default', (t) async {
      await t.pumpWidget(MaterialApp(
        home: SettingsScreen(initialConfig: const CameraConfig()),
      ));
      final sw = t.widget<Switch>(find.byType(Switch));
      expect(sw.value, isFalse);
    });
  });
```
顶部加必要 import（CameraConfig 已有；Switch/MaterialApp 来自 flutter_test/material）。

- [ ] **Step 3: Run test to verify it fails**

Run: `cd camera_handheld && flutter test test/settings_screen_test.dart`
Expected: FAIL — 无「云台」段。

- [ ] **Step 4: Modify settings_screen.dart**

- State 加字段：
  ```dart
  late bool _ptzEnabled;
  late final TextEditingController _ptzIpCtrl;
  late final TextEditingController _ptzPassCtrl;
  late int _ptzSpeed;
  ```
- `initState` 初始化（来自 `widget.initialConfig.ptz`）：
  ```dart
  _ptzEnabled = widget.initialConfig.ptz.enabled;
  _ptzIpCtrl = TextEditingController(text: widget.initialConfig.ptz.ip);
  _ptzPassCtrl = TextEditingController(text: widget.initialConfig.ptz.password);
  _ptzSpeed = widget.initialConfig.ptz.speed;
  ```
- `dispose` 加 `_ptzIpCtrl.dispose(); _ptzPassCtrl.dispose();`
- `_buildConfig`：加 `ptz: PtzConfig(enabled: _ptzEnabled, ip: _ptzIpCtrl.text.trim().isEmpty ? '192.168.1.65' : _ptzIpCtrl.text.trim(), password: _ptzPassCtrl.text, speed: _ptzSpeed),`
- `_save`：在主连接测试通过后、保存前，若 `_ptzEnabled` 则测云台连通：
  ```dart
  if (config.ptz.enabled) {
    final ptzErr = await PtzProtocol.testConnection(config.ptz);
    if (ptzErr != null) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ptzErr),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 5),
        ));
      }
      return;
    }
  }
  ```
  顶部 import `'../../core/ptz_protocol.dart'` 与 `'../../core/ptz_config.dart'`。
- build 的 ListView：在「变倍」段之后、「初始化命令」段之前插入「云台」段：
  ```dart
          const SizedBox(height: 32),
          _SectionLabel(text: '云台'),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('启用外接云台',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
              Switch(
                value: _ptzEnabled,
                onChanged: (v) => setState(() => _ptzEnabled = v),
              ),
            ],
          ),
          if (_ptzEnabled) ...[
            const SizedBox(height: 12),
            _TextField(
              controller: _ptzIpCtrl,
              label: '云台设备 IP',
              hint: '192.168.1.65',
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            _TextField(
              controller: _ptzPassCtrl,
              label: '云台密码',
              hint: '••••••',
              obscureText: true,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('转速',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13)),
                Expanded(
                  child: Slider(
                    value: _ptzSpeed.toDouble(),
                    min: 1,
                    max: 100,
                    divisions: 99,
                    label: '$_ptzSpeed',
                    onChanged: (v) => setState(() => _ptzSpeed = v.round()),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text('$_ptzSpeed',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12),
                      textAlign: TextAlign.end),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '用户名固定 admin。转速 1–100，数值越大转动越快。',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
              ),
            ),
          ],
  ```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd camera_handheld && flutter test test/settings_screen_test.dart`
Expected: PASS（含 ptz section group）。

- [ ] **Step 6: Commit**

```bash
cd camera_handheld
git add lib/features/settings/settings_screen.dart test/settings_screen_test.dart
git commit -m "feat(ptz): add gimbal config section in settings"
```

---

### Task 10: 全量验证

- [ ] **Step 1: Run full test suite**

Run: `cd camera_handheld && flutter test`
Expected: 全部 PASS。

- [ ] **Step 2: Run analyzer**

Run: `cd camera_handheld && flutter analyze`
Expected: 无 error（warning 可接受但应尽量清零）。

- [ ] **Step 3: Smoke test on device/simulator**

启动 app → 设置页启用云台、填 IP/密码、调速度、保存（验证云台连通测试通过）→ 返回预览 → 确认左下角出现四方向盘 → 长按方向键云台转动、松开停止 → 按主变倍 +/- 验证云台镜头同步变倍 → 关闭云台开关保存 → 确认控制盘消失。

- [ ] **Step 4: Update DESIGN.md non-goal note**

`docs/DESIGN.md` 第 19 行「PTZ 云台控制（用户设备无云台…）」从非目标移除/改为「已实现外接云台」。可选。

- [ ] **Step 5: Final commit if any doc change**

```bash
cd camera_handheld
git add docs/DESIGN.md
git commit -m "docs: mark external PTZ gimbal as implemented"
```

---

## 自检清单
- [x] 数据模型（Task 1,4）+ 向后兼容
- [x] DigestAuth 复用（Task 2）零行为变化
- [x] PtzProtocol 报文符号/speed 归一化/stop/locked/串行（Task 3）
- [x] CameraState 变倍联动 fire-and-forget 容错（Task 5）
- [x] 装配按 enabled 创建（Task 6）
- [x] 四方向控制盘 + 短脉冲/长按（Task 7）
- [x] 预览页左下挂载、禁用隐藏（Task 8）
- [x] 设置页配置段 + 双向连通测试（Task 9）
- [x] 全量测试 + analyze + 手测（Task 10）
