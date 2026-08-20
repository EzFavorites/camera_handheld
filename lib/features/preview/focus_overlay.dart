import 'package:flutter/material.dart';

/// Overlay that shows a focus box at the tapped position.
/// Coordinates are normalized to 0-1000 for ISAPI protocol compatibility.
class FocusOverlay extends StatelessWidget {
  final bool visible;
  final int focusX;
  final int focusY;
  final Size viewSize;

  const FocusOverlay({
    super.key,
    required this.visible,
    required this.focusX,
    required this.focusY,
    required this.viewSize,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    // Convert normalized 0-1000 to pixel position.
    final px = (focusX / 1000.0) * viewSize.width;
    final py = (focusY / 1000.0) * viewSize.height;

    return Stack(
      children: [
        Positioned(
          left: px - 40,
          top: py - 40,
          child: IgnorePointer(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.7),
                  width: 1.5,
                ),
              ),
              child: Stack(
                children: [
                  ..._buildCorners(),
                  // Vertical center line
                  Center(
                    child: Container(width: 1, height: 12, color: Colors.white70),
                  ),
                  // Horizontal center line
                  Center(
                    child: Container(width: 12, height: 1, color: Colors.white70),
                  ),
                  // Coordinate label
                  Positioned(
                    bottom: -24,
                    left: 0,
                    right: 0,
                    child: Text(
                      '$focusX, $focusY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                        fontFamily: 'SF Mono',
                        letterSpacing: 0.5,
                      ),
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

  List<Widget> _buildCorners() {
    return [
      Positioned(
        top: -1,
        left: -1,
        child: Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white70, width: 2),
              left: BorderSide(color: Colors.white70, width: 2),
            ),
          ),
        ),
      ),
      Positioned(
        top: -1,
        right: -1,
        child: Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white70, width: 2),
              right: BorderSide(color: Colors.white70, width: 2),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: -1,
        left: -1,
        child: Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white70, width: 2),
              left: BorderSide(color: Colors.white70, width: 2),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: -1,
        right: -1,
        child: Container(
          width: 16,
          height: 16,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white70, width: 2),
              right: BorderSide(color: Colors.white70, width: 2),
            ),
          ),
        ),
      ),
    ];
  }
}