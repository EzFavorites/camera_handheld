import 'package:flutter/material.dart';

/// Shutter button with camera icon.
/// Same size (48px) and visual style as zoom buttons for visual consistency.
/// Shows pressed-state feedback while tapped.
class ShutterButton extends StatefulWidget {
  final VoidCallback onCapture;
  final bool isCapturing;

  const ShutterButton({
    super.key,
    required this.onCapture,
    this.isCapturing = false,
  });

  @override
  State<ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<ShutterButton> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed != value) {
      setState(() => _isPressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onCapture,
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
          child: Icon(
            Icons.camera_alt_outlined,
            color: _isPressed
                ? Colors.white
                : Colors.white.withValues(alpha: 0.85),
            size: 22,
          ),
        ),
      ),
    );
  }
}