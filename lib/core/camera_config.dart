import 'package:flutter/foundation.dart';

/// Camera connection configuration.
/// Persisted via shared_preferences; used to build RTSP URL and future ISAPI client.
@immutable
class CameraConfig {
  final String ip;
  final int port;
  final String username;
  final String password;
  final int channel; // 101=main stream, 102=sub stream
  final bool useSubStream;

  const CameraConfig({
    this.ip = '192.168.1.64',
    this.port = 554,
    this.username = 'admin',
    this.password = '',
    this.channel = 102,
    this.useSubStream = true,
  });

  /// Build RTSP URL from config.
  /// Example: rtsp://admin:pass@192.168.1.64:554/Streaming/Channels/102
  String get rtspUrl {
    final pass = password.isEmpty ? '' : ':${Uri.encodeComponent(password)}';
    final ch = useSubStream ? 102 : 101;
    return 'rtsp://${username}$pass@$ip:$port/Streaming/Channels/$ch';
  }

  /// Base HTTP URL for ISAPI (future use).
  /// Example: http://192.168.1.64:80
  String get httpUrl => 'http://$ip';

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'port': port,
        'username': username,
        'password': password,
        'channel': channel,
        'useSubStream': useSubStream,
      };

  factory CameraConfig.fromJson(Map<String, dynamic> json) => CameraConfig(
        ip: json['ip'] as String? ?? '192.168.1.64',
        port: json['port'] as int? ?? 554,
        username: json['username'] as String? ?? 'admin',
        password: json['password'] as String? ?? '',
        channel: json['channel'] as int? ?? 102,
        useSubStream: json['useSubStream'] as bool? ?? true,
      );

  CameraConfig copyWith({
    String? ip,
    int? port,
    String? username,
    String? password,
    int? channel,
    bool? useSubStream,
  }) =>
      CameraConfig(
        ip: ip ?? this.ip,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
        channel: channel ?? this.channel,
        useSubStream: useSubStream ?? this.useSubStream,
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
          channel == other.channel &&
          useSubStream == other.useSubStream;

  @override
  int get hashCode => Object.hash(ip, port, username, password, channel, useSubStream);
}