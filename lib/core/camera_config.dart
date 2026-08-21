import 'package:flutter/foundation.dart';

import 'init_command.dart';

/// Camera connection configuration.
/// Persisted via shared_preferences; used to build RTSP URL and ISAPI client.
@immutable
class CameraConfig {
  final String ip;
  final int port;
  final String username;
  final String password;
  final bool useSubStream;
  /// Delay (ms) between a single-tap zoom start and the stop command.
  final int zoomTapDelayMs;
  /// Initialization command list sent on first connection.
  final List<InitCommand> initCommands;

  const CameraConfig({
    this.ip = '192.168.1.64',
    this.port = 554,
    this.username = 'admin',
    this.password = '',
    this.useSubStream = true,
    this.zoomTapDelayMs = 60,
    this.initCommands = InitCommand.defaults,
  });

  /// Build RTSP URL from config.
  /// Example: rtsp://admin:pass@192.168.1.64:554/Streaming/Channels/102
  String get rtspUrl {
    final user = Uri.encodeComponent(username);
    final pass =
        password.isEmpty ? '' : ':${Uri.encodeComponent(password)}';
    final ch = useSubStream ? 102 : 101;
    return 'rtsp://$user$pass@$ip:$port/Streaming/Channels/$ch';
  }

  /// Masked RTSP URL for UI display.
  String get rtspUrlMasked {
    final user = Uri.encodeComponent(username);
    final pass = password.isEmpty ? '' : ':••••';
    final ch = useSubStream ? 102 : 101;
    return 'rtsp://$user$pass@$ip:$port/Streaming/Channels/$ch';
  }

  /// Base HTTP URL for ISAPI.
  String get httpUrl => 'http://$ip';

  /// Full JSON, including the password. For debugging / round-trip only.
  Map<String, dynamic> toJson() => {
        'ip': ip,
        'port': port,
        'username': username,
        'password': password,
        'useSubStream': useSubStream,
        'zoomTapDelayMs': zoomTapDelayMs,
        'initCommands': initCommands.map((c) => c.toJson()).toList(),
      };

  factory CameraConfig.fromJson(Map<String, dynamic> json) => CameraConfig(
        ip: json['ip'] as String? ?? '192.168.1.64',
        port: json['port'] as int? ?? 554,
        username: json['username'] as String? ?? 'admin',
        password: json['password'] as String? ?? '',
        useSubStream: json['useSubStream'] as bool? ?? true,
        zoomTapDelayMs: json['zoomTapDelayMs'] as int? ?? 60,
        initCommands: _parseInitCommands(json['initCommands']),
      );

  static List<InitCommand> _parseInitCommands(dynamic raw) {
    if (raw is! List || raw.isEmpty) return InitCommand.defaults;
    try {
      final list = raw
          .whereType<Map<String, dynamic>>()
          .map(InitCommand.fromJson)
          .toList();
      return list.isEmpty ? InitCommand.defaults : list;
    } catch (_) {
      return InitCommand.defaults;
    }
  }

  CameraConfig copyWith({
    String? ip,
    int? port,
    String? username,
    String? password,
    bool? useSubStream,
    int? zoomTapDelayMs,
    List<InitCommand>? initCommands,
  }) =>
      CameraConfig(
        ip: ip ?? this.ip,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
        useSubStream: useSubStream ?? this.useSubStream,
        zoomTapDelayMs: zoomTapDelayMs ?? this.zoomTapDelayMs,
        initCommands: initCommands ?? this.initCommands,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraConfig &&
          runtimeType == other.runtimeType &&
          ip == other.ip &&
          port == other.port &&
          username == other.username &&
          password == other.password &&
          useSubStream == other.useSubStream &&
          zoomTapDelayMs == other.zoomTapDelayMs &&
          listEquals(initCommands, other.initCommands);

  @override
  int get hashCode => Object.hash(ip, port, username, password, useSubStream, zoomTapDelayMs, Object.hashAll(initCommands));
}