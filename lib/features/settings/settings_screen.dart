import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/camera_config.dart';
import '../../core/camera_config_store.dart';
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
  late bool _useSubStream;
  bool _obscurePassword = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ipCtrl = TextEditingController(text: widget.initialConfig.ip);
    _portCtrl = TextEditingController(text: widget.initialConfig.port.toString());
    _userCtrl = TextEditingController(text: widget.initialConfig.username);
    _passCtrl = TextEditingController(text: widget.initialConfig.password);
    _useSubStream = widget.initialConfig.useSubStream;
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  CameraConfig _buildConfig() {
    return CameraConfig(
      ip: _ipCtrl.text.trim().isEmpty ? '192.168.1.64' : _ipCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 554,
      username: _userCtrl.text.trim().isEmpty ? 'admin' : _userCtrl.text.trim(),
      password: _passCtrl.text,
      useSubStream: _useSubStream,
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final config = _buildConfig();
    await CameraConfigStore.save(config);
    if (mounted) {
      // Push config into CameraState for the app to rebuild RTSP URL.
      context.read<CameraState>().updateConfig(config);
      Navigator.of(context).pop(config);
    }
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
          const SizedBox(height: 40),
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
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存并连接'),
            ),
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
  const _StreamSelector({required this.useSubStream, required this.onChanged});

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