import 'dart:async';

import 'package:flutter/material.dart';

/// Vertical zoom +/- buttons with track indicator.
/// Long-press triggers continuous zoom, release stops.
/// A quick tap sends a short zoom pulse: start immediately, then stop after
/// [zoomTapDelayMs] so the camera has time to register the movement.
/// Buttons show pressed-state feedback (highlight + scale) while held.
class ZoomControls extends StatefulWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomStop;
  final double zoomLevel;
  /// Delay (ms) between a single-tap zoom start and the stop command.
  /// Too short a gap and the camera won't move. Config-driven, default 60 ms.
  final int zoomTapDelayMs;

  const ZoomControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomStop,
    required this.zoomLevel,
    this.zoomTapDelayMs = 60,
  });

  @override
  State<ZoomControls> createState() => _ZoomControlsState();
}

class _ZoomControlsState extends State<ZoomControls> {
  bool _isHoldingIn = false;
  bool _isHoldingOut = false;

  void _startZoomIn() {
    _isHoldingIn = true;
    widget.onZoomIn();
  }

  void _stopZoomIn() {
    if (_isHoldingIn) {
      _isHoldingIn = false;
      widget.onZoomStop();
    }
  }

  void _startZoomOut() {
    _isHoldingOut = true;
    widget.onZoomOut();
  }

  void _stopZoomOut() {
    if (_isHoldingOut) {
      _isHoldingOut = false;
      widget.onZoomStop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final trackPercent = ((widget.zoomLevel - 1.0) / 31.0 * 100).clamp(0.0, 100.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ZoomButton(
          label: '+',
          onZoomStart: _startZoomIn,
          onZoomStop: _stopZoomIn,
          tapStopDelayMs: widget.zoomTapDelayMs,
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 2,
          height: 40,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Container(
                width: 2,
                height: 40,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              Positioned(
                top: trackPercent / 100 * 34,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white54,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _ZoomButton(
          label: '\u2212',
          onZoomStart: _startZoomOut,
          onZoomStop: _stopZoomOut,
          tapStopDelayMs: widget.zoomTapDelayMs,
        ),
      ],
    );
  }
}

class _ZoomButton extends StatefulWidget {
  final String label;
  final VoidCallback onZoomStart;
  final VoidCallback onZoomStop;
  final int tapStopDelayMs;

  const _ZoomButton({
    required this.label,
    required this.onZoomStart,
    required this.onZoomStop,
    required this.tapStopDelayMs,
  });

  @override
  State<_ZoomButton> createState() => _ZoomButtonState();
}

class _ZoomButtonState extends State<_ZoomButton> {
  bool _isPressed = false;
  Timer? _stopTimer;

  void _setPressed(bool value) {
    if (_isPressed != value) {
      setState(() => _isPressed = value);
    }
  }

  /// Quick tap -> start zoom now, schedule stop after the configured delay so
  /// the camera has time to react. Long-press uses [onZoomStart]/[onZoomStop]
  /// directly via [onLongPressStart]/[onLongPressEnd] and never schedules here.
  void _onTap() {
    widget.onZoomStart();
    _stopTimer?.cancel();
    _stopTimer = Timer(
      Duration(milliseconds: widget.tapStopDelayMs),
      () {
        if (mounted) widget.onZoomStop();
      },
    );
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: _onTap,
      onLongPressStart: (_) {
        _setPressed(true);
        widget.onZoomStart();
      },
      onLongPressEnd: (_) {
        _stopTimer?.cancel();
        _setPressed(false);
        widget.onZoomStop();
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
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.15),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 120),
            style: TextStyle(
              color: _isPressed ? Colors.white : Colors.white.withValues(alpha: 0.85),
              fontSize: 22,
              fontWeight: FontWeight.w300,
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}
