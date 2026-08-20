import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../core/camera_config.dart';
import '../../core/reconnect_policy.dart';
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

  // Error stream subscription of the currently mounted Player. Cancelled on
  // every rebuild / disposal so a stale listener never fires for an orphaned
  // Player. (P2-11)
  StreamSubscription<String>? _errorSub;

  // Reconnection state. Pure scheduling logic lives in [ReconnectPolicy].
  final ReconnectPolicy _reconnectPolicy = ReconnectPolicy(maxAttempts: 5);
  bool _reconnecting = false;

  // Generation token: bumped on every _rebuildPlayer call so concurrent /
  // superseded rebuilds can detect they are stale and bail out before touching
  // shared state. (P1-2 / P1-3)
  int _rebuildGen = 0;

  @override
  void initState() {
    super.initState();
    context.read<CameraState>().addListener(_onStateChanged);
    _initPlayerIfNeeded();
  }

  void _onStateChanged() => _initPlayerIfNeeded();

  @override
  void dispose() {
    _focusTimer?.cancel();
    context.read<CameraState>().removeListener(_onStateChanged);
    _errorSub?.cancel();
    _errorSub = null;
    // Dispose the live Player. VideoController (media_kit_video 2.0.1) does not
    // expose a public dispose(); its platform resources are released when the
    // bound Player is disposed, so there is nothing else to tear down. (P2-12)
    _player?.dispose();
    _player = null;
    _videoController = null;
    super.dispose();
  }

  void _initPlayerIfNeeded() {
    if (!mounted) return;
    final state = context.read<CameraState>();
    if (state.configVersion == _configVersion) return;
    _configVersion = state.configVersion;
    // User-initiated rebuild (settings/config change): use the default
    // isRetry = false so the reconnect counters are reset inside _rebuildPlayer.
    unawaited(_rebuildPlayer(state.config.rtspUrl));
  }

  /// Rebuilds the media_kit [Player] for [rtspUrl].
  ///
  /// [isRetry] distinguishes a user-initiated rebuild (config changed, which
  /// must reset the reconnect counters) from an automatic reconnect attempt
  /// (which must keep counting). (P0-1)
  Future<void> _rebuildPlayer(String rtspUrl, {bool isRetry = false}) async {
    final state = context.read<CameraState>();
    final myGen = ++_rebuildGen;

    // A user-initiated rebuild (config changed) clears reconnect counters so
    // the stream gets a fresh set of attempts. Retries keep the running count.
    if (!isRetry) {
      _reconnectPolicy.reset();
      _reconnecting = false;
    }

    await _disposePlayer();

    final player = Player(
      configuration: PlayerConfiguration(
        osc: false,
      ),
    );
    final controller = VideoController(player);

    // Guard (a): a newer rebuild started (or the widget was disposed) while we
    // awaited disposal. Dispose the unused Player to avoid leaks.
    if (myGen != _rebuildGen || !mounted) {
      await player.dispose();
      return;
    }

    setState(() {
      _player = player;
      _videoController = controller;
      _playerReady = false;
    });

    _errorSub = player.stream.error.listen((error) {
      debugPrint('Player error: $error');
      // Ignore errors from a superseded / stale Player.
      if (myGen != _rebuildGen || !mounted) return;
      state.setDisconnected();
      setState(() => _playerReady = false);
      // Avoid scheduling duplicates while a reconnect is already pending.
      if (!_reconnecting) _scheduleReconnect(state.config.rtspUrl);
    });

    try {
      await player.open(Media(rtspUrl));
      await player.setVolume(0);
      // Guard (b): a newer rebuild superseded this one while opening, or the
      // widget was disposed. Dispose the now-orphaned Player to avoid leaks.
      if (myGen != _rebuildGen || !mounted) {
        // Only dispose if this is still the live Player; a newer rebuild (or
        // widget.dispose) may have already disposed it — Player.dispose() is
        // NOT idempotent and throws on a second call.
        if (identical(player, _player)) {
          await player.dispose();
        }
        return;
      }
      _reconnectPolicy.reset();
      _reconnecting =  false;
      state.setConnected();
      state.setStreamInfo(
        state.config.useSubStream ? '子码流' : '主码流',
      );
      setState(() => _playerReady = true);
    } catch (e) {
      debugPrint('Player open error: $e');
      if (mounted) {
        state.setDisconnected();
        setState(() => _playerReady = false);
        // Avoid scheduling duplicates while a reconnect is already pending.
        if (!_reconnecting) _scheduleReconnect(state.config.rtspUrl);
      }
    }
  }

  /// Schedule a reconnect with exponential backoff (1, 2, 4, 8, 16 s).
  /// Gives up after [_maxReconnectAttempts] attempts. (P0-1)
  void _scheduleReconnect(String rtspUrl) {
    final delay = _reconnectPolicy.nextDelay();
    if (delay == null) {
      debugPrint('[Preview] Max reconnect attempts reached; giving up.');
      _reconnecting = false;
      return;
    }
    _reconnecting = true;
    debugPrint('[Preview] Reconnect #${_reconnectPolicy.attempts} in ${delay.inSeconds}s');
    Future.delayed(delay, () {
      if (mounted) {
        unawaited(_rebuildPlayer(rtspUrl, isRetry: true));
      }
    });
  }

  Future<void> _disposePlayer() async {
    await _errorSub?.cancel();
    _errorSub = null;
    // VideoController (media_kit_video 2.0.1) does not expose a public
    // dispose(); its platform resources are released when the bound Player is
    // disposed, so we only dispose the Player here. (P2-12)
    await _player?.dispose();
    _player = null;
    _videoController = null;
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
