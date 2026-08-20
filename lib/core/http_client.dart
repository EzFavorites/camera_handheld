import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Result of an HTTP request: status line, decoded body, raw bytes, and any
/// `WWW-Authenticate` challenge header (used internally for digest retries).
class HttpResponse {
  final int statusCode;
  final String body;
  final List<int> bytes;
  final String? wwwAuthenticate;

  const HttpResponse(this.statusCode, this.body, this.bytes, [this.wwwAuthenticate]);

  bool get ok => statusCode >= 200 && statusCode < 300;
}

/// Abstraction over an HTTP client so the protocol layer can be unit-tested
/// without a real camera / network.
abstract class HttpRequester {
  Future<HttpResponse> request(
    String method,
    String path, {
    String? body,
    Map<String, String>? headers,
  });
}

/// HTTP client with transparent HTTP Digest authentication for Hikvision ISAPI.
///
/// Cameras expose ISAPI over HTTP and require Digest auth; this wrapper performs
/// the 401 -> challenge -> retry handshake manually so it works deterministically
/// across platforms without depending on `dart:io`'s callback quirks.
class DigestHttpClient implements HttpRequester {
  DigestHttpClient({
    required this.baseUrl,
    required this.username,
    required this.password,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final String baseUrl;
  final String username;
  final String password;
  final HttpClient _client;

  @override
  Future<HttpResponse> request(
    String method,
    String path, {
    String? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    var response = await _send(method, uri, body, headers, null);
    if (response.statusCode == 401 && response.wwwAuthenticate != null) {
      final challenge = response.wwwAuthenticate!;
      if (challenge.toLowerCase().startsWith('digest')) {
        final header = _digestHeader(method, path, challenge);
        response = await _send(method, uri, body, headers, header);
      }
    }
    return response;
  }

  Future<HttpResponse> _send(
    String method,
    Uri uri,
    String? body,
    Map<String, String>? headers,
    String? auth,
  ) async {
    final req = await _client.openUrl(method, uri);
    if (auth != null) req.headers.set('Authorization', auth);
    if (headers != null) {
      headers.forEach((k, v) => req.headers.set(k, v));
    }
    if (body != null) {
      req.headers.contentType = ContentType('application', 'xml', charset: 'utf-8');
      req.write(body);
    }
    final resp = await req.close();
    final bytes = <int>[];
    await for (final chunk in resp) {
      bytes.addAll(chunk);
    }
    final wwwAuth = resp.headers.value('www-authenticate');
    return HttpResponse(
      resp.statusCode,
      String.fromCharCodes(bytes),
      bytes,
      wwwAuth,
    );
  }

  /// Build a Digest `Authorization` header from a `WWW-Authenticate` challenge.
  String _digestHeader(String method, String path, String challenge) {
    final params = _parseChallenge(challenge);
    final realm = params['realm'] ?? '';
    final nonce = params['nonce'] ?? '';
    final qop = (params['qop'] ?? '').split(',').firstWhere(
          (q) => q.trim() == 'auth',
          orElse: () => '',
        );

    final ha1 = _md5('$username:$realm:$password');
    final ha2 = _md5('$method:$path');
    final response = qop.isNotEmpty
        ? _md5('$ha1:$nonce:00000001:${_cnonce()}:auth:$ha2')
        : _md5('$ha1:$nonce:$ha2');

    final buf = StringBuffer()
      ..write('Digest username="$username"')
      ..write(', realm="$realm"')
      ..write(', nonce="$nonce"')
      ..write(', uri="$path"')
      ..write(', response="$response"');
    if (qop.isNotEmpty) {
      buf.write(', qop=auth, nc=00000001, cnonce="${_cnonce()}"');
    }
    return buf.toString();
  }

  Map<String, String> _parseChallenge(String challenge) {
    // Strip the leading "Digest " and split key="value" pairs.
    final map = <String, String>{};
    final body = challenge.substring(challenge.indexOf(' ') + 1);
    for (final pair in body.split(',')) {
      final idx = pair.indexOf('=');
      if (idx < 0) continue;
      final key = pair.substring(0, idx).trim();
      var value = pair.substring(idx + 1).trim();
      if (value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      map[key] = value;
    }
    return map;
  }

  String _md5(String input) =>
      md5.convert(utf8.encode(input)).toString();

  String _cnonce() {
    final rnd = Random.secure();
    return List<int>.generate(8, (_) => rnd.nextInt(16))
        .map((e) => e.toRadixString(16))
        .join();
  }
}
