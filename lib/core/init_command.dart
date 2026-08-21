/// A single initialization command sent to the camera on first connection.
///
/// Two types:
/// - [InitCommandType.visca]: sends a VISCA hex string via the MovementMgr
///   endpoint. `content` is the hex payload (e.g. `8101045707ff`).
/// - [InitCommandType.isapi]: sends an HTTP request to an ISAPI endpoint.
///   `method` + `path` + `content` (body) define the request.
///
/// Extendable — add new commands from the settings screen without code changes.
class InitCommand {
  /// Display name shown in settings (e.g. "PDAF 聚焦模式").
  final String name;

  /// Command type.
  final InitCommandType type;

  /// HTTP method for [InitCommandType.isapi] (ignored for visca).
  final String method;

  /// ISAPI endpoint path for [InitCommandType.isapi] (ignored for visca).
  final String path;

  /// VISCA hex (no spaces) for visca; request body for isapi.
  final String content;

  /// Whether this command runs during initialization.
  final bool enabled;

  const InitCommand({
    this.name = '',
    this.type = InitCommandType.visca,
    this.method = 'POST',
    this.path = '',
    this.content = '',
    this.enabled = true,
  });

  /// Default command set: PDAF focus mode (2 VISCA commands) + noise reduce.
  static const List<InitCommand> defaults = [
    InitCommand(
      name: 'PDAF 聚焦模式',
      type: InitCommandType.visca,
      content: '8101045707ff',
    ),
    InitCommand(
      name: 'PDAF 模式确认',
      type: InitCommandType.visca,
      content: '8101043802ff',
    ),
    InitCommand(
      name: '降噪',
      type: InitCommandType.isapi,
      method: 'PUT',
      path: '/ISAPI/Image/channels/1/noiseReduce',
      content:
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<NoiseReduce><mode>general</mode>'
          '<GeneralMode><generalLevel>50</generalLevel></GeneralMode>'
          '</NoiseReduce>',
    ),
  ];

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.name,
        'method': method,
        'path': path,
        'content': content,
        'enabled': enabled,
      };

  factory InitCommand.fromJson(Map<String, dynamic> json) => InitCommand(
        name: json['name'] as String? ?? '',
        type: InitCommandType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => InitCommandType.visca,
        ),
        method: json['method'] as String? ?? 'POST',
        path: json['path'] as String? ?? '',
        content: json['content'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
      );

  InitCommand copyWith({
    String? name,
    InitCommandType? type,
    String? method,
    String? path,
    String? content,
    bool? enabled,
  }) =>
      InitCommand(
        name: name ?? this.name,
        type: type ?? this.type,
        method: method ?? this.method,
        path: path ?? this.path,
        content: content ?? this.content,
        enabled: enabled ?? this.enabled,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InitCommand &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          type == other.type &&
          method == other.method &&
          path == other.path &&
          content == other.content &&
          enabled == other.enabled;

  @override
  int get hashCode => Object.hash(name, type, method, path, content, enabled);
}

enum InitCommandType { visca, isapi }