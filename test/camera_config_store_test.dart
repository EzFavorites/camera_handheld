import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera_handheld/core/ptz_config.dart';
import 'package:camera_handheld/core/camera_config.dart';
import 'package:camera_handheld/core/camera_config_store.dart';

void main() {
  group('CameraConfigStore', () {
    test('save then load round-trips all fields', () async {
      SharedPreferences.setMockInitialValues({});
      const config = CameraConfig(
        ip: '10.0.0.5',
        port: 8080,
        username: 'operator',
        password: 's3cr3t!@#',
        useSubStream: false,
        zoomTapDelayMs: 120,
      );
      await CameraConfigStore.save(config);
      final loaded = await CameraConfigStore.load();
      expect(loaded.ip, config.ip);
      expect(loaded.port, config.port);
      expect(loaded.username, config.username);
      // NOTE: per current design (v1) the password is persisted as-is via
      // shared_preferences (plaintext). This test verifies store round-trip
      // behavior, not an endorsement of plaintext storage.
      expect(loaded.password, config.password);
      expect(loaded.useSubStream, config.useSubStream);
      expect(loaded.zoomTapDelayMs, config.zoomTapDelayMs);
    });

    test('load returns defaults when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final loaded = await CameraConfigStore.load();
      expect(loaded.ip, '192.168.1.64');
      expect(loaded.port, 554);
      expect(loaded.username, 'admin');
      expect(loaded.password, '');
      expect(loaded.useSubStream, isTrue);
    });

    test('save overwrites the previously stored config', () async {
      SharedPreferences.setMockInitialValues({});
      await CameraConfigStore.save(const CameraConfig(ip: '1.1.1.1', password: 'old'));
      await CameraConfigStore.save(const CameraConfig(ip: '2.2.2.2', password: 'new'));
      final loaded = await CameraConfigStore.load();
      expect(loaded.ip, '2.2.2.2');
      expect(loaded.password, 'new');
    });

    test('toSafeJson omits the password field', () {
      const config = CameraConfig(ip: '10.0.0.5', password: 'topsecret');
      final safe = config.toSafeJson();
      expect(safe.containsKey('password'), isFalse);
      final ptzSafe = const PtzConfig(enabled: true, password: 'ptzpass').toSafeJson();
      expect(ptzSafe.containsKey('password'), isFalse);
      expect(ptzSafe['enabled'], isTrue);
    });
  });
}
