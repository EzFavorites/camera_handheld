import 'package:camera_handheld/core/camera_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CameraConfig.rtspUrl', () {
    test('uses sub stream (102) by default', () {
      const config = CameraConfig(ip: '192.168.1.64');
      expect(
        config.rtspUrl,
        'rtsp://admin@192.168.1.64:554/Streaming/Channels/102',
      );
    });

    test('uses main stream (101) when useSubStream is false', () {
      const config = CameraConfig(useSubStream: false);
      expect(
        config.rtspUrl,
        'rtsp://admin@192.168.1.64:554/Streaming/Channels/101',
      );
    });

    test('embeds password URL-encoded', () {
      const config = CameraConfig(password: 'p@ss:word');
      expect(
        config.rtspUrl,
        'rtsp://admin:p%40ss%3Aword@192.168.1.64:554/Streaming/Channels/102',
      );
    });

    test('URL-encodes username with special chars', () {
      const config = CameraConfig(username: 'user@cam');
      expect(
        config.rtspUrl,
        'rtsp://user%40cam@192.168.1.64:554/Streaming/Channels/102',
      );
    });

    test('omits password segment when empty', () {
      const config = CameraConfig(password: '');
      expect(config.rtspUrl, contains('rtsp://admin@'));
    });
  });

  group('CameraConfig serialization', () {
    test('toJson includes password (debug contract)', () {
      const config = CameraConfig(
        ip: '10.0.0.5',
        port: 8554,
        username: 'operator',
        password: 'secret',
        useSubStream: false,
      );
      final json = config.toJson();
      expect(json.containsKey('password'), isTrue);
      expect(json['password'], 'secret');
      final restored = CameraConfig.fromJson(json);
      expect(restored, equals(config));
      expect(restored.password, 'secret');
    });

    test('toPersistableJson omits password', () {
      const config = CameraConfig(
        ip: '10.0.0.5',
        port: 8554,
        username: 'operator',
        password: 'secret',
        useSubStream: false,
      );
      final json = config.toPersistableJson();
      expect(json.containsKey('password'), isFalse);
      // Non-sensitive fields are present.
      expect(json['ip'], '10.0.0.5');
      expect(json['port'], 8554);
      expect(json['username'], 'operator');
      expect(json['useSubStream'], isFalse);
      // fromJson still round-trips (password defaults to empty string).
      final restored = CameraConfig.fromJson(json);
      expect(restored.ip, '10.0.0.5');
      expect(restored.port, 8554);
      expect(restored.username, 'operator');
      expect(restored.password, '');
    });

    test('fromJson tolerates missing fields', () {
      final restored = CameraConfig.fromJson(<String, dynamic>{'ip': '1.2.3.4'});
      expect(restored.ip, '1.2.3.4');
      expect(restored.port, 554);
      expect(restored.useSubStream, isTrue);
    });
  });

  group('CameraConfig.rtspUrlMasked', () {
    test('masks the password segment with ••••', () {
      const config = CameraConfig(
        ip: '192.168.1.64',
        password: 'p@ss:word',
      );
      expect(
        config.rtspUrlMasked,
        'rtsp://admin:••••@192.168.1.64:554/Streaming/Channels/102',
      );
    });

    test('omits the password segment when empty', () {
      const config = CameraConfig(password: '');
      expect(config.rtspUrlMasked, contains('rtsp://admin@'));
      expect(config.rtspUrlMasked, isNot(contains('••••')));
    });

    test('hides the raw password in the masked URL', () {
      const config = CameraConfig(password: 'supersecret');
      expect(config.rtspUrlMasked, contains(':••••'));
      expect(config.rtspUrlMasked, isNot(contains('supersecret')));
    });
  });

  group('CameraConfig.copyWith', () {
    test('overrides only provided fields', () {
      const base = CameraConfig();
      final updated = base.copyWith(ip: '192.168.0.1', useSubStream: false);
      expect(updated.ip, '192.168.0.1');
      expect(updated.useSubStream, isFalse);
      expect(updated.port, base.port);
      expect(updated.username, base.username);
    });
  });
}
