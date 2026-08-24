import 'package:flutter_test/flutter_test.dart';
import 'package:camera_handheld/core/app_log.dart';

void main() {
  group('AppLog', () {
    setUp(() {
      AppLog.clear();
    });

    test('starts empty', () {
      expect(AppLog.snapshot(), isEmpty);
    });

    test('log adds entries in order', () {
      AppLog.log('line one');
      AppLog.log('line two');
      final lines = AppLog.snapshot();
      expect(lines.length, 2);
      expect(lines[0], contains('line one'));
      expect(lines[1], contains('line two'));
    });

    test('log includes timestamp', () {
      AppLog.log('test');
      final lines = AppLog.snapshot();
      // Timestamp format: HH:MM:SS.mmm
      expect(lines[0], matches(r'^\d{2}:\d{2}:\d{2}\.\d{3} test$'));
    });

    test('maxEntries caps buffer size', () {
      for (var i = 0; i < 600; i++) {
        AppLog.log('msg_$i');
      }
      final lines = AppLog.snapshot();
      expect(lines.length, lessThanOrEqualTo(500));
    });

    test('newest entries retained when overflow', () {
      for (var i = 0; i < 501; i++) {
        AppLog.log('old_$i');
      }
      AppLog.log('new_entry');
      final lines = AppLog.snapshot();
      expect(lines.last, contains('new_entry'));
      expect(lines.first, isNot(contains('old_0')));
    });

    test('addListener receives each new line', () {
      final received = <String>[];
      AppLog.addListener(received.add);
      AppLog.log('test msg');
      expect(received, hasLength(1));
      expect(received[0], contains('test msg'));
    });

    test('removeListener stops callbacks', () {
      final received = <String>[];
      AppLog.addListener(received.add);
      AppLog.removeListener(received.add);
      AppLog.log('ignored');
      expect(received, isEmpty);
    });

    test('clear resets all entries', () {
      AppLog.log('keep me');
      AppLog.clear();
      expect(AppLog.snapshot(), isEmpty);
    });
  });
}
