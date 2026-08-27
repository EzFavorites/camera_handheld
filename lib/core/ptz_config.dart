import 'package:flutter/foundation.dart';

/// 外接云台设备配置。用户名固定 admin。
/// 持久化随 CameraConfig 一起存储。
@immutable
class PtzConfig {
  final bool enabled;
  final String ip;
  final String password;
  /// 转动/变倍速度，1..100，归一化为 0.01..1.0 下发。
  final int speed;

  const PtzConfig({
    this.enabled = false,
    this.ip = '192.168.1.65',
    this.password = '',
    this.speed = 50,
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'ip': ip,
        'password': password,
        'speed': speed,
      };

  /// Safe JSON that omits the password (for logging / crash reporting).
  Map<String, dynamic> toSafeJson() => {
        'enabled': enabled,
        'ip': ip,
        'speed': speed,
      };

  factory PtzConfig.fromJson(Map<String, dynamic> json) => PtzConfig(
        enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
        ip: json['ip'] is String ? json['ip'] as String : '192.168.1.65',
        password: json['password'] is String ? json['password'] as String : '',
        speed: _clampSpeed(json['speed'] is int ? json['speed'] as int : 50),
      );

  static int _clampSpeed(int v) => v.clamp(1, 100);

  /// 归一化速度 (0.01..1.0)，用于 ISAPI PTZData。
  double get normalizedSpeed => speed / 100.0;

  PtzConfig copyWith({
    bool? enabled,
    String? ip,
    String? password,
    int? speed,
  }) =>
      PtzConfig(
        enabled: enabled ?? this.enabled,
        ip: ip ?? this.ip,
        password: password ?? this.password,
        speed: speed ?? this.speed,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PtzConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          ip == other.ip &&
          password == other.password &&
          speed == other.speed;

  @override
  int get hashCode => Object.hash(enabled, ip, password, speed);
}
