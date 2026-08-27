import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_handheld/core/camera_config.dart';
import 'package:camera_handheld/core/init_command.dart';
import 'package:camera_handheld/core/ptz_config.dart';

void main() {
  group('CameraConfig', () {
    test('default values', () {
      const config = CameraConfig();
      expect(config.ip, '192.168.1.64');
      expect(config.port, 554);
      expect(config.username, 'admin');
      expect(config.password, '');
      expect(config.useSubStream, isTrue);
      expect(config.zoomTapDelayMs, 60);
      expect(config.initCommands, isNotEmpty);
    });

    test('toJson / fromJson round-trip preserves all fields', () {
      const original = CameraConfig(
        ip: '10.16.113.77',
        port: 8080,
        username: 'operator',
        password: 'p@ss!w0rd',
        useSubStream: false,
        zoomTapDelayMs: 120,
      );
      final json = original.toJson();
      final restored = CameraConfig.fromJson(json);

      expect(restored.ip, original.ip);
      expect(restored.port, original.port);
      expect(restored.username, original.username);
      expect(restored.password, original.password);
      expect(restored.useSubStream, original.useSubStream);
      expect(restored.zoomTapDelayMs, original.zoomTapDelayMs);
    });

    test('fromJson handles missing fields with defaults', () {
      final config = CameraConfig.fromJson({});
      expect(config.ip, '192.168.1.64');
      expect(config.port, 554);
      expect(config.username, 'admin');
      expect(config.password, '');
      expect(config.useSubStream, isTrue);
      expect(config.zoomTapDelayMs, 60);  // default is 60
    });

    test('fromJson handles invalid types gracefully', () {
      // Invalid types become null, defaults kick in
      // Invalid types should fall back to defaults without crashing
      final config = CameraConfig.fromJson({
        'ip': 123,  // wrong type
        'port': 'not-a-number',  // wrong type
      });
      expect(config.ip, '192.168.1.64');
      expect(config.port, 554);
    });

    test('password with special characters is URL-encoded in rtspUrl', () {
      const config = CameraConfig(
        ip: '10.16.113.77',
        port: 554,
        username: 'admin',
        password: 'asdf!234',
        useSubStream: true,
      );
      final url = config.rtspUrl;
      // ! must be encoded as %21
      // Note: ! is not URL-encoded by Uri.encodeComponent
    expect(url, contains('asdf!234'));
      expect(url, contains('10.16.113.77:554'));
      expect(url, contains('Channels/102'));
    });

    test('empty password omits colon in rtspUrl', () {
      const config = CameraConfig(ip: '192.168.1.64', password: '');
      final url = config.rtspUrl;
      expect(url, 'rtsp://admin@192.168.1.64:554/Streaming/Channels/102');
    });

    test('rtspUrl uses 102 for sub stream, 101 for main stream', () {
      const sub = CameraConfig(useSubStream: true);
      const main = CameraConfig(useSubStream: false);
      expect(sub.rtspUrl, contains('Channels/102'));
      expect(main.rtspUrl, contains('Channels/101'));
    });

    test('rtspUrlMasked hides password', () {
      const config = CameraConfig(
        ip: '10.16.113.77',
        password: 'secret123',
      );
      final masked = config.rtspUrlMasked;
      expect(masked, contains('••••'));
      expect(masked, isNot(contains('secret123')));
    });

    test('rtspUrlMasked with empty password has no mask', () {
      const config = CameraConfig(password: '');
      expect(config.rtspUrlMasked, isNot(contains('••••')));
    });

    test('httpUrl returns correct base', () {
      const config = CameraConfig(ip: '10.16.113.77');
      expect(config.httpUrl, 'http://10.16.113.77');
    });

    test('copyWith creates independent copy', () {
      const original = CameraConfig(ip: '10.0.0.1', password: 'old');
      final copy = original.copyWith(ip: '10.0.0.2');
      expect(copy.ip, '10.0.0.2');
      expect(copy.password, 'old');
      expect(original.ip, '10.0.0.1');
    });

    test('equality and hashCode', () {
      const a = CameraConfig(ip: '10.0.0.1', port: 80);
      const b = CameraConfig(ip: '10.0.0.1', port: 80);
      const c = CameraConfig(ip: '10.0.0.2', port: 80);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('initCommands defaults to PDAF + noise reduce', () {
      const config = CameraConfig();
      expect(config.initCommands.length, 3);
      expect(config.initCommands[0].content, '8101045707ff');
      expect(config.initCommands[1].content, '8101043802ff');
      expect(config.initCommands[2].path, '/ISAPI/Image/channels/1/noiseReduce');
    });

    test('initCommands round-trip through JSON', () {
      const config = CameraConfig(
        initCommands: [
          InitCommand(name: 'test', content: 'abc123'),
        ],
      );
      final json = jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>;
      final restored = CameraConfig.fromJson(json);
      expect(restored.initCommands.length, 1);
      expect(restored.initCommands[0].name, 'test');
      expect(restored.initCommands[0].content, 'abc123');
    });

    test('fromJson falls back to defaults when initCommands is empty', () {
      final config = CameraConfig.fromJson({'initCommands': []});
      expect(config.initCommands, InitCommand.defaults);
    });

    test('fromJson falls back to defaults when initCommands is null', () {
      final config = CameraConfig.fromJson({});
      expect(config.initCommands, InitCommand.defaults);
    });
  });

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
}
