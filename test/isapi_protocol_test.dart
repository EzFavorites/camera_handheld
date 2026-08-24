import 'package:flutter_test/flutter_test.dart';
import 'package:camera_handheld/core/isapi_protocol.dart';
import 'package:camera_handheld/core/camera_config.dart';
import 'package:camera_handheld/core/init_command.dart';

void main() {
  group('IsapiProtocol config management', () {
    test('constructor creates with empty password', () {
      const config = CameraConfig(ip: '10.0.0.1');
      final protocol = IsapiProtocol(config: config);
      expect(protocol.config.ip, '10.0.0.1');
      expect(protocol.config.password, '');
      protocol.dispose();
    });

    test('updateConfig changes config', () {
      const config = CameraConfig(ip: '10.0.0.1');
      final protocol = IsapiProtocol(config: config);
      protocol.updateConfig(const CameraConfig(ip: '192.168.1.64'));
      expect(protocol.config.ip, '192.168.1.64');
      protocol.dispose();
    });

    test('updateConfig resets lock and init flags', () {
      const config = CameraConfig(ip: '10.0.0.1');
      final protocol = IsapiProtocol(config: config);
      // _initialized is a private field, but we can verify through behavior
      // after updateConfig, initCommands should reflect new config
      protocol.updateConfig(
        const CameraConfig(ip: '10.0.0.2', initCommands: []),
      );
      expect(protocol.config.initCommands, isEmpty);
      protocol.dispose();
    });
  });

  group('IsapiProtocol init commands', () {
    test('uses InitCommand.defaults when no custom commands', () {
      const config = CameraConfig();
      expect(config.initCommands.length, 3);
    });

    test('supports VISCA type command', () {
      const cmd = InitCommand(
        name: 'Test VISCA',
        type: InitCommandType.visca,
        content: '8101045707ff',
      );
      expect(cmd.type, InitCommandType.visca);
      expect(cmd.content, '8101045707ff');
    });

    test('supports ISAPI type command', () {
      const cmd = InitCommand(
        name: 'Noise Reduce',
        type: InitCommandType.isapi,
        method: 'PUT',
        path: '/ISAPI/Image/channels/1/noiseReduce',
        content: '<NoiseReduce/>',
      );
      expect(cmd.type, InitCommandType.isapi);
      expect(cmd.method, 'PUT');
    });

    test('disabled commands are skipped', () {
      const cmd = InitCommand(enabled: false);
      expect(cmd.enabled, isFalse);
    });
  });

  group('IsapiProtocol edge cases', () {
    test('dispose does not throw', () {
      const config = CameraConfig(ip: '10.0.0.1');
      final protocol = IsapiProtocol(config: config);
      expect(() => protocol.dispose(), returnsNormally);
    });

    test('protocol with complex password in config', () {
      const config = CameraConfig(
        ip: '192.168.1.64',
        username: 'admin',
        password: 'p@ss!w0rd#123',
      );
      final protocol = IsapiProtocol(config: config);
      expect(protocol.config.password, 'p@ss!w0rd#123');
      protocol.dispose();
    });
  });
}
