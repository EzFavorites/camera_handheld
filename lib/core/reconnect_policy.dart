/// Pure reconnect scheduling policy (exponential backoff, capped attempts).
///
/// Extracted from [PreviewScreen] so the reconnection state machine is testable
/// without a widget / Player. The widget keeps its own `mounted`/`setState`
/// concerns; this class owns only the attempt counting and delay math.
class ReconnectPolicy {
  final int maxAttempts;
  int _attempts = 0;

  ReconnectPolicy({this.maxAttempts = 5});

  /// Number of attempts made so far.
  int get attempts => _attempts;

  /// True once the maximum number of attempts has been exhausted.
  bool get gaveUp => _attempts >= maxAttempts;

  /// Returns the delay for the next reconnect attempt, or `null` if the limit is
  /// reached (meaning the caller should give up and reset the in-flight flag).
  Duration? nextDelay() {
    if (_attempts >= maxAttempts) return null;
    final delay = Duration(seconds: 1 << _attempts); // 1, 2, 4, 8, 16...
    _attempts++;
    return delay;
  }

  /// Reset the counter (used when a connection succeeds or the user changes config).
  void reset() => _attempts = 0;
}
