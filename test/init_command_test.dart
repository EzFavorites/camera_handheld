import 'package:flutter_test/flutter_test.dart';
import 'package:camera_handheld/core/init_command.dart';

void main() {
  group('InitCommand', () {
    test('defaults are sensible', () {
      const cmd = InitCommand();
      expect(cmd.name, '');
      expect(cmd.type, InitCommandType.visca);
      expect(cmd.method, 'POST');
      expect(cmd.path, '');
      expect(cmd.content, '');
      expect(cmd.enabled, isTrue);
    });

    test('fromJson parses all fields', () {
      final cmd = InitCommand.fromJson({
        'name': 'PDAF',
        'type': 'visca',
        'method': 'POST',
        'path': '/test',
        'content': '8101045707ff',
        'enabled': false,
      });
      expect(cmd.name, 'PDAF');
      expect(cmd.type, InitCommandType.visca);
      expect(cmd.method, 'POST');
      expect(cmd.path, '/test');
      expect(cmd.content, '8101045707ff');
      expect(cmd.enabled, isFalse);
    });

    test('fromJson handles unknown type by defaulting to visca', () {
      final cmd = InitCommand.fromJson({'type': 'unknown_type'});
      expect(cmd.type, InitCommandType.visca);
    });

    test('fromJson handles missing fields gracefully', () {
      final cmd = InitCommand.fromJson({});
      expect(cmd.name, '');
      expect(cmd.method, 'POST');
      expect(cmd.path, '');
      expect(cmd.content, '');
      expect(cmd.enabled, isTrue);
    });

    test('toJson round-trip preserves data', () {
      const original = InitCommand(
        name: 'test_cmd',
        type: InitCommandType.isapi,
        method: 'PUT',
        path: '/ISAPI/Image/channels/1/noiseReduce',
        content: '<?xml version="1.0"?><NoiseReduce/>',
        enabled: false,
      );
      final json = original.toJson();
      final restored = InitCommand.fromJson(json);
      expect(restored.name, original.name);
      expect(restored.type, original.type);
      expect(restored.method, original.method);
      expect(restored.path, original.path);
      expect(restored.content, original.content);
      expect(restored.enabled, original.enabled);
    });

    test('copyWith creates independent copy', () {
      const original = InitCommand(name: 'a', content: '123', enabled: true);
      final copy = original.copyWith(name: 'b', enabled: false);
      expect(copy.name, 'b');
      expect(copy.content, '123');
      expect(copy.enabled, isFalse);
      expect(original.name, 'a');
      expect(original.enabled, isTrue);
    });

    test('equality', () {
      const a = InitCommand(name: 'x', content: 'abc');
      const b = InitCommand(name: 'x', content: 'abc');
      const c = InitCommand(name: 'y', content: 'abc');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('InitCommandType values', () {
      expect(InitCommandType.values, [InitCommandType.visca, InitCommandType.isapi]);
    });

    test('defaults has 3 commands', () {
      expect(InitCommand.defaults.length, 3);
      expect(InitCommand.defaults[0].type, InitCommandType.visca);
      expect(InitCommand.defaults[1].type, InitCommandType.visca);
      expect(InitCommand.defaults[2].type, InitCommandType.isapi);
    });

    test('defaults values match expected VISCA commands', () {
      const defaults = InitCommand.defaults;
      expect(defaults[0].content, '8101045707ff');
      expect(defaults[1].content, '8101043802ff');
      expect(defaults[2].method, 'PUT');
      expect(defaults[2].path, '/ISAPI/Image/channels/1/noiseReduce');
    });
  });
}
