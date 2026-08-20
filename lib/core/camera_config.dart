import 'package:flutter/foundation.dart';

/// Camera connection configuration.
/// Persisted via shared_preferences; used to build RTSP URL and future ISAPI client.
@immutable
class CameraConfig {
  final String ip;
  final int port;
  final String username;
  final String password;
  final bool useSubStream;
  /// Delay (ms) between a single-tap zoom start and the stop command.
  /// A tap sends ZOOM start then stops; too short a gap and the camera won't
  /// move. Default 60 ms. Configurable in settings.
  final int zoomTapDelayMs;

  const CameraConfig({
    this.ip = '192.168.1.64',
    this.port = 554,
    this.username = 'admin',
    this.password = '',
    this.useSubStream = true,
    this.zoomTapDelayMs = 60,
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

  /// Masked RTSP URL for UI display: the password segment is replaced with
  /// `:••••` so the secret is never shown in plaintext. (P1-5)
  /// Example: rtsp://admin:••••@192.168.1.64:554/Streaming/Channels/102
  String get rtspUrlMasked {
    final user = Uri.encodeComponent(username);
    final pass = password.isEmpty ? '' : ':••••';
    final ch = useSubStream ? 102 : 101;
    return 'rtsp://$user$pass@$ip:$port/Streaming/Channels/$ch';
  }

  /// Base HTTP URL for ISAPI (future use).
  /// Example: http://192.168.1.64:80
  String get httpUrl => 'http://$ip';

  /// Full JSON, including the password. Intended for debugging / round-trip
  /// only — never persist this to disk. (P2-13)
  Map<String, dynamic> toJson() => {
        'ip': ip,
        'port':  port,
        'username': username,
        'password': password,
        'useSubStream': useSubStream,
        'zoomTapDelayMs': zoomTapDelayMs,
      };

  /// Persistable JSON, deliberately excluding the password. The password is
  /// stored separately in flutter_secure_storage. Use this for persistence
  /// instead of [toJson]. (P2-13)
  Map<String, dynamic> toPersistableJson() => {
        'ip': ip,
        'port': port,
        'username': username,
        'useSubStream': useSubStream,
        'zoomTapDelayMs': zoomTapDelayMs,
      };

  factory CameraConfig.fromJson(Map<String, dynamic> json) => CameraConfig(
        ip: json['ip'] as String? ?? '192.168.1.64',
        port: json['port'] as int? ?? 554,
        username: json['username'] as String? ?? 'admin',
        password: json['password'] as String? ?? '',
        useSubStream: json['useSubStream'] as bool? ?? true,
        zoomTapDelayMs: json['zoomTapDelayMs'] as int? ?? 60,
      );

  CameraConfig copyWith({
    String? ip,
    int? port,
    String? username,
    String? password,
    bool? useSubStream,
    int? zoomTapDelayMs,
  }) =>
      CameraConfig(
        ip: ip ?? this.ip,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
        useSubStream: useSubStream ?? this.useSubStream,
        zoomTapDelayMs: zoomTapDelayMs ?? this.zoomTapDelayMs,
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
          zoomTapDelayMs == other.zoomTapDelayMs;

  @override
  int get hashCode => Object.hash(ip, port, username, password, useSubStream, zoomTapDelayMs);
}
