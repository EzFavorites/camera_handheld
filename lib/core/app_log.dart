import 'dart:collection';

import 'package:flutter/foundation.dart';

/// In-memory log buffer for the app.
///
/// Captures all [AppLog.log] entries and exposes them to the log viewer
/// screen. Keeps the last [AppLog.maxEntries] entries, newest last.
class AppLog {
  AppLog._();

  static const int maxEntries = 500;

  /// Ring buffer of log entries.
  static final Queue<String> _entries = Queue<String>();

  static final List<ValueChanged<String>> _listeners = [];

  /// Returns a snapshot of all current log lines.
  static List<String> snapshot() => List.unmodifiable(_entries);

  /// Registers a listener called with each new log line.
  static void addListener(ValueChanged<String> listener) {
    _listeners.add(listener);
  }

  static void removeListener(ValueChanged<String> listener) {
    _listeners.remove(listener);
  }

  /// Appends a log line with timestamp.
  static void log(String message) {
    final line = '${_timestamp()} $message';
    _entries.addLast(line);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    debugPrint(line);
    for (final listener in List.of(_listeners)) {
      listener(line);
    }
  }

  static String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
  }

  static void clear() {
    _entries.clear();
  }
}