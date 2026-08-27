import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Application logger.
///
/// Captures every [log] entry into an in-memory ring buffer (for the log
/// viewer) AND appends it to a file on disk so crashes and the run-up to them
/// can be inspected post-mortem. The file lives in the platform's per-app
/// documents/support directory and is rotated once it exceeds [maxFileBytes]
/// (the previous file is kept as `app.log.1`).
///
/// Call [init] once at startup (after bindings are ready), then [log] freely.
/// Uncaught framework/platform errors are wired in via [recordError] so a
/// hard crash still leaves a trace on disk before the process dies.
class AppLog {
  AppLog._();

  static const int maxEntries = 500;

  /// Max log file size before rotation. 2 MiB keeps hours of verbose logs
  /// while staying small enough to share.
  static const int maxFileBytes = 2 * 1024 * 1024;

  /// Ring buffer of log entries.
  static final Queue<String> _entries = Queue<String>();

  static final List<ValueChanged<String>> _listeners = [];

  /// Append-only file sink. Lazily opened on first [log] after [init].
  static IOSink? _sink;
  static String? _filePath;
  static bool _initialized = false;
  static final _writeQueue = _AsyncSerializer();

  /// Resolve and prepare the log file. Safe to call once at app startup;
  /// subsequent calls are no-ops. Never throws — file logging is best-effort.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final dir = await _logDirectory();
      await dir.create(recursive: true);
      _filePath = '${dir.path}${Platform.pathSeparator}app.log';
      await _rotateIfNeeded();
      _sink = File(_filePath!).openWrite(mode: FileMode.append);
      // Stderr mirror so `flutter run` / console also sees the logs.
      log('--- AppLog session started ---');
    } catch (e) {
      // Logging must never break the app; fall back to in-memory only.
      _initialized = false;
      _filePath = null;
      debugPrint('[AppLog] init failed, file logging disabled: $e');
    }
  }

  /// Platform-appropriate directory for the log file.
  ///
  /// - Windows / macOS / Linux desktop: the app support directory (alongside
  ///   other app data).
  /// - Android: external files directory (user-accessible, easy to share).
  /// - iOS: documents directory.
  static Future<Directory> _logDirectory() async {
    // Desktop + iOS: support dir is stable and survives reinstalls' data.
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return getApplicationSupportDirectory();
    }
    // Mobile: prefer external (shareable) storage on Android, documents on iOS.
    if (Platform.isAndroid) {
      final ext = await getExternalStorageDirectory();
      return ext ?? await getApplicationDocumentsDirectory();
    }
    return getApplicationDocumentsDirectory();
  }

  /// Absolute path of the active log file, or null if file logging is off.
  /// Exposed for the log viewer ("打开日志文件夹") button.
  static String? get filePath => _filePath;

  /// Returns a snapshot of all current log lines.
  static List<String> snapshot() => List.unmodifiable(_entries);

  /// Registers a listener called with each new log line.
  static void addListener(ValueChanged<String> listener) {
    _listeners.add(listener);
  }

  static void removeListener(ValueChanged<String> listener) {
    _listeners.remove(listener);
  }

  /// Appends a log line with timestamp, to both the in-memory buffer and the
  /// file sink (best-effort, serialized).
  static void log(String message) {
    final line = '${_timestamp()} $message';
    _entries.addLast(line);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    debugPrint(line);
    _writeQueue.run(() async {
      _sink?.writeln(line);
      // Cheap rotation check on a cadence, not every line.
      if (_sink != null && _writeQueue.count % 64 == 0) {
        await _rotateIfNeeded();
      }
    });
    for (final listener in List.of(_listeners)) {
      listener(line);
    }
  }

  /// Record an error / stack trace. Used by the global error hooks so that a
  /// fatal exception is flushed to disk before the process tears down.
  static void recordError(Object error, StackTrace? stack,
      {String? context}) {
    final ctx = context == null ? '' : '($context) ';
    log('CRASH $ctx$error');
    if (stack != null) {
      for (final frame in stack.toString().split('\n').take(40)) {
        if (frame.trim().isNotEmpty) log('  $frame');
      }
    }
    // Force a flush so the trace is on disk before a hard exit.
    flush();
  }

  /// Flush pending writes and close the sink. Call on app shutdown.
  static Future<void> dispose() async {
    await flush();
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }

  /// Flush buffered file writes immediately (e.g. right before a crash).
  static Future<void> flush() async {
    await _writeQueue.flush();
    await _sink?.flush();
  }

  static void clear() {
    _entries.clear();
    _writeQueue.run(() async {
      await _sink?.flush();
    });
  }

  static String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
  }

  /// Rotates the log file to `app.log.1` when it exceeds [maxFileBytes].
  /// Called on startup and periodically during logging so a runaway file is
  /// trimmed: the current file is renamed to the backup, then a fresh file is
  /// opened for appending.
  static Future<void> _rotateIfNeeded() async {
    final path = _filePath;
    if (path == null) return;
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final size = await file.length();
      if (size <= maxFileBytes) return;
      await _sink?.flush();
      await _sink?.close();
      _sink = null;
      final backup = File('$path.1');
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
      _sink = File(path).openWrite(mode: FileMode.append);
    } catch (e) {
      debugPrint('[AppLog] rotate failed: $e');
    }
  }
}

/// Tiny FIFO serializer: ensures file writes from concurrent [log] calls never
/// interleave. Tracks a monotonic counter for cadence checks.
class _AsyncSerializer {
  final List<Future<void> Function()> _pending = [];
  bool _running = false;
  int count = 0;

  Future<void> run(Future<void> Function() task) async {
    _pending.add(task);
    if (_running) return;
    _running = true;
    try {
      while (_pending.isNotEmpty) {
        final next = _pending.removeAt(0);
        try {
          await next();
          count++;
        } catch (_) {
          // Best-effort: a failed write must not stop the serializer.
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> flush() async {
    // Drain by running until idle.
    while (_running) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}
