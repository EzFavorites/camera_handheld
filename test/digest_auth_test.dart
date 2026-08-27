import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:camera_handheld/core/digest_auth.dart';

void main() {
  group('DigestAuth', () {
    test('parseParams extracts realm/nonce/qop/opaque', () {
      final header = 'Digest realm="testrealm@host.com", '
          'nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", '
          'qop="auth", opaque="5ccc069c403ebaf9f0171e9517f40e41"';
      final params = DigestAuth.parseParams(header);
      expect(params['realm'], 'testrealm@host.com');
      expect(params['nonce'], 'dcd98b7102dd2f0e8b11d0f600bfb0c093');
      expect(params['qop'], 'auth');
      expect(params['opaque'], '5ccc069c403ebaf9f0171e9517f40e41');
    });

    test('parseParams handles header without leading "Digest"', () {
      final params = DigestAuth.parseParams('realm="r", nonce="n"');
      expect(params['realm'], 'r');
      expect(params['nonce'], 'n');
    });

    test('generateCnonce returns a decodable 8-byte base64 string', () {
      final cnonce = DigestAuth.generateCnonce();
      final bytes = base64Decode(cnonce);
      expect(bytes.length, 8);
    });

    test('buildHeader matches RFC 2617 example vector', () {
      // RFC 2617 §3.5 example:
      //   username="Mufasa", password="Circle Of Life",
      //   realm="testrealm@host.com",
      //   nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093",
      //   uri="/dir/index.html", qop="auth", nc=00000001, cnonce="0a4f113b"
      //   -> response = "6629fae49393a05397450978507c4ef1"
      final header = DigestAuth(
        username: 'Mufasa',
        password: 'Circle Of Life',
      ).buildHeader(
        method: 'GET',
        uriPath: '/dir/index.html',
        params: {
          'realm': 'testrealm@host.com',
          'nonce': 'dcd98b7102dd2f0e8b11d0f600bfb0c093',
          'qop': 'auth',
        },
        cnonce: '0a4f113b',
        nc: 1,
      );

      expect(header, startsWith('Digest '));
      expect(header, contains('username="Mufasa"'));
      expect(header, contains('realm="testrealm@host.com"'));
      expect(header, contains('nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093"'));
      expect(header, contains('uri="/dir/index.html"'));
      expect(header, contains('qop=auth'));
      expect(header, contains('nc=00000001'));
      expect(header, contains('cnonce="0a4f113b"'));

      // Extract the computed response and compare against the known vector.
      final match = RegExp(r'response="([^"]*)"').firstMatch(header);
      expect(match, isNotNull);
      expect(match!.group(1), '6629fae49393a05397450978507c4ef1');
    });

    test('buildHeader changes when cnonce changes', () {
      final base = {
        'realm': 'r',
        'nonce': 'n',
        'qop': 'auth',
      };
      final a = DigestAuth(username: 'u', password: 'p').buildHeader(
        method: 'GET',
        uriPath: '/x',
        params: base,
        cnonce: 'aaaaaaaa',
        nc: 1,
      );
      final b = DigestAuth(username: 'u', password: 'p').buildHeader(
        method: 'GET',
        uriPath: '/x',
        params: base,
        cnonce: 'bbbbbbbb',
        nc: 1,
      );
      expect(a, isNot(equals(b)));
    });

    test('buildHeader is deterministic for identical inputs', () {
      final base = {
        'realm': 'r',
        'nonce': 'n',
        'qop': 'auth',
      };
      final a = DigestAuth(username: 'u', password: 'p').buildHeader(
        method: 'GET',
        uriPath: '/x',
        params: base,
        cnonce: 'cccccccc',
        nc: 2,
      );
      final b = DigestAuth(username: 'u', password: 'p').buildHeader(
        method: 'GET',
        uriPath: '/x',
        params: base,
        cnonce: 'cccccccc',
        nc: 2,
      );
      expect(a, equals(b));
    });
  });
}
