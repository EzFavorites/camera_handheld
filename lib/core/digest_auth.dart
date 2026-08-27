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
