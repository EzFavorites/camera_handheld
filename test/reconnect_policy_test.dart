import 'package:camera_handheld/core/reconnect_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delays follow 1,2,4,8,16 then give up', () {
    final p = ReconnectPolicy(maxAttempts: 5);
    expect(p.attempts, 0);
    expect(p.nextDelay(), const Duration(seconds: 1));
    expect(p.attempts, 1);
    expect(p.nextDelay(), const Duration(seconds: 2));
    expect(p.nextDelay(), const Duration(seconds: 4));
    expect(p.nextDelay(), const Duration(seconds: 8));
    expect(p.nextDelay(), const Duration(seconds: 16));
    // 5th attempt exhausted the budget.
    expect(p.nextDelay(), isNull);
    expect(p.gaveUp, isTrue);
    // Further calls keep returning null.
    expect(p.nextDelay(), isNull);
  });

  test('reset restores scheduling', () {
    final p = ReconnectPolicy(maxAttempts: 5);
    p.nextDelay();
    p.nextDelay();
    expect(p.attempts, 2);
    p.reset();
    expect(p.attempts, 0);
    expect(p.gaveUp, isFalse);
    expect(p.nextDelay(), const Duration(seconds: 1));
  });
}
