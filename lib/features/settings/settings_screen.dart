import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/camera_config.dart';
import '../../core/camera_config_store.dart';
import '../../core/init_command.dart';
import '../../core/isapi_protocol.dart';
import '../../core/ptz_config.dart';
import '../../core/ptz_protocol.dart';
import 'log_viewer_screen.dart';
import '../camera_state.dart';

/// Settings screen for camera connection configuration.
/// Fields: IP, port, username, password, stream type (main/sub).
class SettingsScreen extends StatefulWidget {
  final CameraConfig initialConfig;

  const SettingsScreen({super.key, required this.initialConfig});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _ipCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _zoomDelayCtrl;
  late bool _useSubStream;
  late List<InitCommand> _initCommands;
  late bool _ptzEnabled;
  late final TextEditingController _ptzIpCtrl;
  late final TextEditingController _ptzPassCtrl;
  late int _ptzSpeed;
  bool _obscurePassword = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ipCtrl = TextEditingController(text: widget.initialConfig.ip);
    _portCtrl = TextEditingController(text: widget.initialConfig.port.toString());
    _userCtrl = TextEditingController(text: widget.initialConfig.username);
    _passCtrl = TextEditingController(text: widget.initialConfig.password);
    _zoomDelayCtrl =
        TextEditingController(text: widget.initialConfig.zoomTapDelayMs.toString());
    _useSubStream = widget.initialConfig.useSubStream;
    _initCommands = List.of(widget.initialConfig.initCommands);
    _ptzEnabled = widget.initialConfig.ptz.enabled;
    _ptzIpCtrl = TextEditingController(text: widget.initialConfig.ptz.ip);
    _ptzPassCtrl = TextEditingController(text: widget.initialConfig.ptz.password);
    _ptzSpeed = widget.initialConfig.ptz.speed;
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _zoomDelayCtrl.dispose();
    _ptzIpCtrl.dispose();
    _ptzPassCtrl.dispose();
    super.dispose();
  }

  CameraConfig _buildConfig() {
    return CameraConfig(
      ip: _ipCtrl.text.trim().isEmpty ? '192.168.1.64' : _ipCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 554,
      username: _userCtrl.text.trim().isEmpty ? 'admin' : _userCtrl.text.trim(),
      password: _passCtrl.text,
      useSubStream: _useSubStream,
      zoomTapDelayMs: int.tryParse(_zoomDelayCtrl.text.trim()) ?? 60,
      initCommands: List.of(_initCommands),
      ptz: PtzConfig(
        enabled: _ptzEnabled,
        ip: _ptzIpCtrl.text.trim().isEmpty ? '192.168.1.65' : _ptzIpCtrl.text.trim(),
        password: _ptzPassCtrl.text,
        speed: _ptzSpeed,
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final config = _buildConfig();

    // Test connection with ISAPI before saving to avoid device lock.
    try {
      final error = await IsapiProtocol.testConnection(config);
      if (error != null) {
        if (mounted) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error),
              backgroundColor: Colors.red.shade800,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection test failed: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
      return;
    }

    // Test PTZ gimbal connection before saving (only when enabled).
    if (config.ptz.enabled) {
      try {
        final ptzError = await PtzProtocol.testConnection(config.ptz);
        if (ptzError != null) {
          if (mounted) {
            setState(() => _saving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ptzError),
                backgroundColor: Colors.red.shade800,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PTZ connection test failed: $e'),
              backgroundColor: Colors.red.shade800,
            ),
          );
        }
        return;
      }
    }

    // Connection successful — save config.
    try {
      await CameraConfigStore.save(config);
      if (mounted) {
        context.read<CameraState>().updateConfig(config);
        Navigator.of(context).pop(config);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  List<Widget> _buildInitCommandEditor() {
    final tiles = <Widget>[
      for (var i = 0; i < _initCommands.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _InitCommandTile(
            command: _initCommands[i],
            onChanged: (updated) {
              setState(() => _initCommands[i] = updated);
            },
            onDelete: () {
              setState(() => _initCommands.removeAt(i));
            },
          ),
        ),
    ];
    tiles.add(
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            setState(() {
              _initCommands.add(const InitCommand(name: '新命令'));
            });
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('添加命令'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white70,
          ),
        ),
      ),
    );
    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '设备配置',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          _SectionLabel(text: '网络'),
          const SizedBox(height: 8),
          _TextField(
            controller: _ipCtrl,
            label: '设备 IP 地址',
            hint: '192.168.1.64',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          _TextField(
            controller: _portCtrl,
            label: 'RTSP 端口',
            hint: '554',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 32),
          _SectionLabel(text: '认证'),
          const SizedBox(height: 8),
          _TextField(
            controller: _userCtrl,
            label: '用户名',
            hint: 'admin',
          ),
          const SizedBox(height: 16),
          _TextField(
            controller: _passCtrl,
            label: '密码',
            hint: '••••••',
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.white38,
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          const SizedBox(height: 32),
          _SectionLabel(text: '码流'),
          const SizedBox(height: 8),
          _StreamSelector(
            useSubStream: _useSubStream,
            onChanged: (v) => setState(() => _useSubStream = v),
          ),
          const SizedBox(height: 32),
          _SectionLabel(text: '变倍'),
          const SizedBox(height: 8),
          _TextField(
            controller: _zoomDelayCtrl,
            label: '单点变倍延时 (ms)',
            hint: '60',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 32),
          _SectionLabel(text: '云台'),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '启用外接云台',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                ),
              ),
              Switch(
                key: const ValueKey('ptz_enable_switch'),
                value: _ptzEnabled,
                onChanged: (v) => setState(() => _ptzEnabled = v),
              ),
            ],
          ),
          if (_ptzEnabled) ...[
            const SizedBox(height: 12),
            _TextField(
              controller: _ptzIpCtrl,
              label: '云台设备 IP',
              hint: '192.168.1.65',
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            _TextField(
              controller: _ptzPassCtrl,
              label: '云台密码',
              hint: '••••••',
              obscureText: true,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '转速',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _ptzSpeed.toDouble(),
                    min: 1,
                    max: 100,
                    divisions: 99,
                    label: '$_ptzSpeed',
                    onChanged: (v) => setState(() => _ptzSpeed = v.round()),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '$_ptzSpeed',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '用户名固定 admin。转速 1–100，数值越大转动越快。主设备变倍时云台同步变倍。',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 40),
          _SectionLabel(text: '初始化命令'),
          const SizedBox(height: 4),
          Text(
            '连接时自动发送，用于切换聚焦模式/降噪等。可添加 VISCA 或 ISAPI 指令。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          ..._buildInitCommandEditor(),
          const SizedBox(height: 12),
          // Preview of generated RTSP URL
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RTSP 地址预览',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _buildConfig().rtspUrlMasked,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontFamily: 'SF Mono',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LogViewerScreen(),
                  ),
                );
              },
              icon: Icon(
                Icons.terminal,
                size: 16,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              label: const Text('查看日志'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              if (_saving)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _saving = false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('取消'),
                  ),
                ),
              if (_saving) const SizedBox(width: 12),
              Expanded(
                flex: _saving ? 2 : 1,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _saving
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('验证中...'),
                          ],
                        )
                      : const Text('保存并连接'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.4),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 2,
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;

  const _TextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
        ),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
            ),
          ),
        ),
      ],
    );
  }
}

class _StreamSelector extends StatelessWidget {
  final bool useSubStream;
  final ValueChanged<bool> onChanged;
  const _StreamSelector({
    required this.useSubStream,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(true),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: useSubStream
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: useSubStream
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '子码流',
                    style: TextStyle(
                      color: useSubStream ? Colors.white : Colors.white54,
                      fontSize: 14,
                      fontWeight: useSubStream ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  Text(
                    '低延迟预览',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(false),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: !useSubStream
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: !useSubStream
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '主码流',
                    style: TextStyle(
                      color: !useSubStream ? Colors.white : Colors.white54,
                      fontSize: 14,
                      fontWeight: !useSubStream ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  Text(
                    '高画质',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Editable tile for a single init command in settings.
class _InitCommandTile extends StatefulWidget {
  final InitCommand command;
  final ValueChanged<InitCommand> onChanged;
  final VoidCallback onDelete;

  const _InitCommandTile({
    required this.command,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_InitCommandTile> createState() => _InitCommandTileState();
}

class _InitCommandTileState extends State<_InitCommandTile> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _pathCtrl;
  late InitCommandType _type;
  late String _method;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.command.name);
    _contentCtrl = TextEditingController(text: widget.command.content);
    _pathCtrl = TextEditingController(text: widget.command.path);
    _type = widget.command.type;
    _method = widget.command.method;
    _enabled = widget.command.enabled;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contentCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(InitCommand(
      name: _nameCtrl.text.trim(),
      type: _type,
      method: _method,
      path: _pathCtrl.text.trim(),
      content: _contentCtrl.text,
      enabled: _enabled,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isVisca = _type == InitCommandType.visca;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Switch(
                value: _enabled,
                onChanged: (v) {
                  setState(() => _enabled = v);
                  _emit();
                },
                activeThumbColor: Colors.white70,
                activeTrackColor: Colors.white24,
                inactiveThumbColor: Colors.white38,
                inactiveTrackColor: Colors.white10,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  onChanged: (_) => _emit(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '命令名称',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
                    filled: true,
                    fillColor: Colors.transparent,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    enabled: _enabled,
                  ),
                  style: TextStyle(
                    color: _enabled ? Colors.white70 : Colors.white30,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onDelete,
                icon: Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Row(
            children: [
              _typeChip('VISCA', InitCommandType.visca),
              const SizedBox(width: 8),
              _typeChip('ISAPI', InitCommandType.isapi),
            ],
          ),
          const SizedBox(height: 10),
          if (isVisca) ...[
            _miniField(
              controller: _contentCtrl,
              hint: 'VISCA HEX (无空格，如 8101045707ff)',
              onChanged: (_) => _emit(),
            ),
          ] else ...[
            Row(
              children: [
                DropdownButton<String>(
                  value: _method,
                  onChanged: _enabled
                      ? (v) {
                          if (v != null) {
                            setState(() => _method = v);
                            _emit();
                          }
                        }
                      : null,
                  dropdownColor: const Color(0xFF1A1A1A),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  items: ['GET', 'POST', 'PUT']
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                ),
                Expanded(
                  child: _miniField(
                    controller: _pathCtrl,
                    hint: 'ISAPI 路径 (如 /ISAPI/Image/channels/1/noiseReduce)',
                    onChanged: (_) => _emit(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _miniField(
              controller: _contentCtrl,
              hint: '请求体 (XML/JSON 文本)',
              maxLines: 3,
              onChanged: (_) => _emit(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _typeChip(String label, InitCommandType type) {
    final selected = _type == type;
    return GestureDetector(
      onTap: _enabled
          ? () {
              setState(() => _type = type);
              _emit();
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white70 : Colors.white30,
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _miniField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      maxLines: maxLines,
      enabled: _enabled,
      style: TextStyle(
        color: _enabled ? Colors.white70 : Colors.white30,
        fontSize: 12,
        fontFamily: _useMonoFont(controller) ? 'SF Mono' : null,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.2),
          fontSize: 11,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  bool _useMonoFont(TextEditingController controller) =>
      controller == _contentCtrl && _type == InitCommandType.visca;
}
