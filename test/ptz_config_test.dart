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
