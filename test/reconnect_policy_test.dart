import 'package:flutter_test/flutter_test.dart';
import 'package:camera_handheld/core/reconnect_policy.dart';

void main() {
  group('ReconnectPolicy', () {
    test('backoff sequence 1,2,4,8,16s then null (gives up)', () {
      final policy = ReconnectPolicy(maxAttempts: 5);
      expect(policy.nextDelay()?.inSeconds, 1);
      expect(policy.nextDelay()?.inSeconds, 2);
      expect(policy.nextDelay()?.inSeconds, 4);
      expect(policy.nextDelay()?.inSeconds, 8);
      expect(policy.nextDelay()?.inSeconds, 16);
      expect(policy.nextDelay(), isNull); // gave up after 5 attempts
    });

    test('default maxAttempts is 5', () {
      final policy = ReconnectPolicy();
      expect(policy.maxAttempts, 5);
      for (var i = 0; i < 5; i++) {
        expect(policy.nextDelay(), isNotNull);
      }
      expect(policy.nextDelay(), isNull);
    });

    test('gaveUp reflects exhaustion', () {
      final policy = ReconnectPolicy(maxAttempts: 3);
      expect(policy.gaveUp, isFalse);
      expect(policy.attempts, 0);
      policy.nextDelay();
      policy.nextDelay();
      expect(policy.gaveUp, isFalse);
      policy.nextDelay();
      expect(policy.gaveUp, isTrue);
      expect(policy.attempts, 3);
    });

    test('reset clears the attempt counter', () {
      final policy = ReconnectPolicy(maxAttempts: 2);
      policy.nextDelay();
      policy.nextDelay();
      expect(policy.nextDelay(), isNull);
      policy.reset();
      expect(policy.gaveUp, isFalse);
      expect(policy.attempts, 0);
      expect(policy.nextDelay()?.inSeconds, 1);
    });

    test('custom maxAttempts controls give-up point', () {
      final policy = ReconnectPolicy(maxAttempts: 1);
      expect(policy.nextDelay()?.inSeconds, 1);
      expect(policy.nextDelay(), isNull);
    });
  });
}
