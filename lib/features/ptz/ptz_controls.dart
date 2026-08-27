import 'dart:async';

import 'package:flutter/material.dart';

enum PtzDirection { up, down, left, right }

/// 四方向云台控制盘。长按连续移动，短按脉冲（tapStopDelayMs 后 stop）。
/// disabled 时返回 SizedBox.shrink。
class PtzControls extends StatelessWidget {
  final bool enabled;
  final int tapStopDelayMs;
  final ValueChanged<PtzDirection> onMove;
  final VoidCallback onStop;

  const PtzControls({
    super.key,
    required this.enabled,
    required this.tapStopDelayMs,
    required this.onMove,
    required this.onStop,
  });

  Widget _dir(PtzDirection d, IconData icon) => _PtzDirButton(
        icon: icon,
        onStart: () => onMove(d),
        onStop: onStop,
        tapStopDelayMs: tapStopDelayMs,
      );

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return SizedBox(
      width: 152,
      height: 152,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(top: 0, child: _dir(PtzDirection.up, Icons.arrow_drop_up)),
          Positioned(bottom: 0, child: _dir(PtzDirection.down, Icons.arrow_drop_down)),
          Positioned(left: 0, child: _dir(PtzDirection.left, Icons.arrow_left)),
          Positioned(right: 0, child: _dir(PtzDirection.right, Icons.arrow_right)),
        ],
      ),
    );
  }
}

class _PtzDirButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final int tapStopDelayMs;

  const _PtzDirButton({
    required this.icon,
    required this.onStart,
    required this.onStop,
    required this.tapStopDelayMs,
  });

  @override
  State<_PtzDirButton> createState() => _PtzDirButtonState();
}

class _PtzDirButtonState extends State<_PtzDirButton> {
  bool _isPressed = false;
  Timer? _stopTimer;

  @override
  void dispose() {
    _stopTimer?.cancel();
    super.dispose();
  }

  void _setPressed(bool v) {
    if (_isPressed != v) setState(() => _isPressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        widget.onStart();
        _stopTimer?.cancel();
        _stopTimer = Timer(Duration(milliseconds: widget.tapStopDelayMs), () {
          if (mounted) widget.onStop();
        });
      },
      onLongPressStart: (_) {
        _setPressed(true);
        widget.onStart();
      },
      onLongPressEnd: (_) {
        _stopTimer?.cancel();
        _setPressed(false);
        widget.onStop();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: 48,
        height: 48,
        transform: _isPressed
            ? Matrix4.diagonal3Values(0.88, 0.88, 1.0)
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _isPressed
                ? Colors.white.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.25),
            width: _isPressed ? 1.5 : 1,
          ),
          color: _isPressed
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.5),
        ),
        child: Icon(
          widget.icon,
          color: _isPressed ? Colors.white : Colors.white.withValues(alpha: 0.85),
          size: 28,
        ),
      ),
    );
  }
}
