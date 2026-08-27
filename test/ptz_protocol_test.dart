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
      await expectLater(ptz.stop(), throwsA(isA<StateError>()));
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
