import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../core/camera_config.dart';
import '../camera_state.dart';
import '../capture/shutter_button.dart';
import '../lens/zoom_controls.dart';
import '../settings/settings_screen.dart';
import 'focus_overlay.dart';

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  Player? _player;
  VideoController? _videoController;
  bool _playerReady = false;
  Timer? _focusTimer;
  int _configVersion = -1;

  @override
  void initState() {
    super.initState();
  }

  void _initPlayerIfNeeded() {
    final state = context.read<CameraState>();
    if (state.configVersion == _configVersion) return;
    _configVersion = state.configVersion;
    _rebuildPlayer(state.config.rtspUrl);
  }

  Future<void> _rebuildPlayer(String rtspUrl) async {
    await _disposePlayer();
    final player = Player(
      configuration: PlayerConfiguration(
        osc: false,
      ),
    );
    final controller = VideoController(player);
    if (!mounted) {
      player.dispose();
      return;
    }
    setState(() {
      _player = player;
      _videoController = controller;
      _playerReady = false;
    });

    player.stream.error.listen((error) {
      debugPrint('Player error: $error');
      if (mounted) {
        context.read<CameraState>().setDisconnected();
        setState(() => _playerReady = false);
      }
    });

    try {
      await player.open(Media(rtspUrl));
      await player.setVolume(0);
      if (mounted) {
        context.read<CameraState>().setConnected();
        context.read<CameraState>().setStreamInfo(
              rtspUrl.contains('102') ? '子码流' : '主码流',
            );
        setState(() => _playerReady = true);
      }
    } catch (e) {
      debugPrint('Player open error: $e');
      if (mounted) {
        context.read<CameraState>().setDisconnected();
        setState(() => _playerReady = false);
      }
    }
  }

  Future<void> _disposePlayer() async {
    await _player?.dispose();
    _player = null;
    _videoController = null;
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _onTapPreview(TapDownDetails details, Size viewSize) {
    final x = (details.localPosition.dx / viewSize.width * 1000).round();
    final y = (details.localPosition.dy / viewSize.height * 1000).round();
    context.read<CameraState>().focusAt(x, y);

    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        context.read<CameraState>().hideFocus();
      }
    });
  }

  Future<void> _openSettings() async {
    final state = context.read<CameraState>();
    final result = await Navigator.of(context).push<CameraConfig>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(initialConfig: state.config),
      ),
    );
    // If config changed, rebuild the player with the new RTSP URL.
    if (result != null && mounted) {
      // configVersion already bumped in updateConfig; rebuild player.
      _initPlayerIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch configVersion so we rebuild when config changes externally.
    context.watch<CameraState>().configVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) => _initPlayerIfNeeded());

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            children: [
              // ── 视频预览层 ──
              Positioned.fill(
                child: GestureDetector(
                  onTapDown: (details) => _onTapPreview(details, viewSize),
                  child: (_playerReady && _videoController != null)
                      ? Video(
                          controller: _videoController!,
                          fill: Colors.black,
                          fit: BoxFit.contain,
                        )
                      : _buildPlaceholder(),
                ),
              ),

              // ── 对焦框 ──
              Positioned.fill(
                child: Consumer<CameraState>(
                  builder: (context, state, _) => FocusOverlay(
                    visible: state.showFocus,
                    focusX: state.focusX,
                    focusY: state.focusY,
                    viewSize: viewSize,
                  ),
                ),
              ),

              // ── 顶栏（常驻，含设置入口）──
              Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

              // ── 变倍控制（常驻，右侧垂直居中）──
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Consumer<CameraState>(
                    builder: (context, state, _) => ZoomControls(
                      zoomLevel: state.zoomLevel,
                      onZoomIn: () => state.zoomIn(),
                      onZoomOut: () => state.zoomOut(),
                      onZoomStop: () => state.zoomStop(),
                    ),
                  ),
                ),
              ),

              // ── 快门按钮（常驻，右下角）──
              Positioned(
                bottom: 40,
                right: 20,
                child: Consumer<CameraState>(
                  builder: (context, state, _) => ShutterButton(
                    onCapture: () => state.capture(),
                    isCapturing: state.isCapturing,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.only(top: 16, left: 20, right: 12, bottom: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Consumer<CameraState>(
                builder: (context, state, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${state.zoomLevel.toStringAsFixed(1)}\u00d7',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w300,
                        fontFamily: 'SF Mono',
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      'ZOOM',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 设置齿轮入口
              GestureDetector(
                onTap: _openSettings,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.4),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Icon(
                    Icons.settings,
                    color: Colors.white.withValues(alpha: 0.6),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF0A0A0A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_outlined,
              color: Colors.white.withValues(alpha: 0.15),
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              '正在连接视频流...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}