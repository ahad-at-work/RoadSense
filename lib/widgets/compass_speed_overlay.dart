import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Swipeable Compass and Speed Display Overlay
/// Shows real-time heading and speed with swipe-to-hide functionality
class CompassSpeedOverlay extends StatefulWidget {
  final double? heading;
  final double? speedKmh;
  final bool isNavigating;

  const CompassSpeedOverlay({
    super.key,
    this.heading,
    this.speedKmh,
    this.isNavigating = false,
  });

  @override
  State<CompassSpeedOverlay> createState() =>
      CompassSpeedOverlayState(); //  Changed: No underscore
}

class CompassSpeedOverlayState extends State<CompassSpeedOverlay> {
  //  Changed: Public class
  bool _isVisible = false; //  Changed: Hidden by default

  //  NEW: Public method to show compass programmatically
  void show() {
    if (!_isVisible) {
      setState(() {
        _isVisible = true;
      });
    }
  }

  //  NEW: Public method to hide compass programmatically
  void hide() {
    if (_isVisible) {
      setState(() {
        _isVisible = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main compass widget with swipe gesture
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          top: widget.isNavigating ? 260 : 180,
          right: _isVisible ? 16 : -200,
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              if (details.delta.dx > 5) {
                // Swipe right to hide
                setState(() {
                  _isVisible = false;
                });
              } else if (details.delta.dx < -5) {
                // Swipe left to show
                setState(() {
                  _isVisible = true;
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Compass
                  _buildCompass(),

                  const SizedBox(height: 12),

                  // Speed display
                  _buildSpeedDisplay(),

                  // Optional: Heading degrees
                  if (widget.heading != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.heading!.toStringAsFixed(0),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Swipe handle/tab to show compass when hidden
        if (!_isVisible)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            top: widget.isNavigating ? 260 : 180,
            right: 0,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isVisible = true;
                });
              },
              onHorizontalDragUpdate: (details) {
                if (details.delta.dx < -5) {
                  setState(() {
                    _isVisible = true;
                  });
                }
              },
              child: Container(
                width: 32,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue[700]!, Colors.blue[500]!],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(-2, 0),
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.navigation,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(height: 4),
                    Icon(
                      Icons.chevron_left,
                      color: Colors.white,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCompass() {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Compass background circle
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey[300]!,
                width: 2,
              ),
            ),
          ),

          // Compass ring with cardinal marks
          CustomPaint(
            size: const Size(76, 76),
            painter: CompassRingPainter(),
          ),

          // North indicator (fixed at top)
          Positioned(
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'N',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          // Rotating needle
          if (widget.heading != null)
            Transform.rotate(
              angle: widget.heading! * math.pi / 180,
              child: CustomPaint(
                size: const Size(60, 60),
                painter: CompassNeedlePainter(),
              ),
            )
          else
            Icon(
              Icons.navigation,
              color: Colors.grey[400],
              size: 32,
            ),
        ],
      ),
    );
  }

  Widget _buildSpeedDisplay() {
    final speed = widget.speedKmh ?? 0;
    final color = _getSpeedColor(speed);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.speed,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            widget.speedKmh != null
                ? widget.speedKmh!.toStringAsFixed(0)
                : '--',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'km/h',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getSpeedColor(double speed) {
    if (speed < 1) return Colors.grey[600]!;
    if (speed < 20) return const Color(0xFF4CAF50); // Green
    if (speed < 50) return const Color(0xFF2196F3); // Blue
    if (speed < 80) return const Color(0xFFFF9800); // Orange
    if (speed < 100) return const Color(0xFFFF5722); // Deep Orange
    return const Color(0xFFF44336); // Red
  }
}

/// Custom painter for compass ring with cardinal direction marks
class CompassRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paint = Paint()
      ..color = Colors.grey[400]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Draw cardinal direction marks (N, E, S, W)
    for (int i = 0; i < 4; i++) {
      final angle = (i * 90 - 90) * math.pi / 180; // Start from top (North)
      final x1 = center.dx + (radius - 8) * math.cos(angle);
      final y1 = center.dy + (radius - 8) * math.sin(angle);
      final x2 = center.dx + radius * math.cos(angle);
      final y2 = center.dy + radius * math.sin(angle);

      paint.strokeWidth = 2;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }

    // Draw minor marks (8 additional marks)
    paint.strokeWidth = 1;
    for (int i = 0; i < 8; i++) {
      if (i % 2 == 0) continue; // Skip cardinal directions
      final angle = (i * 45 - 90) * math.pi / 180;
      final x1 = center.dx + (radius - 5) * math.cos(angle);
      final y1 = center.dy + (radius - 5) * math.sin(angle);
      final x2 = center.dx + radius * math.cos(angle);
      final y2 = center.dy + radius * math.sin(angle);

      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for compass needle
class CompassNeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final needleLength = size.width / 2 - 10;

    // North needle (red)
    final northPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    final northPath = Path()
      ..moveTo(center.dx, center.dy - needleLength) // Tip
      ..lineTo(center.dx - 5, center.dy) // Left base
      ..lineTo(center.dx + 5, center.dy) // Right base
      ..close();

    canvas.drawPath(northPath, northPaint);

    // South needle (white with border)
    final southPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final southBorderPaint = Paint()
      ..color = Colors.grey[600]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final southPath = Path()
      ..moveTo(center.dx, center.dy + needleLength) // Tip
      ..lineTo(center.dx - 5, center.dy) // Left base
      ..lineTo(center.dx + 5, center.dy) // Right base
      ..close();

    canvas.drawPath(southPath, southPaint);
    canvas.drawPath(southPath, southBorderPaint);

    // Center circle
    final centerPaint = Paint()
      ..color = Colors.grey[700]!
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 4, centerPaint);

    final centerBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(center, 4, centerBorderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Compact version for when space is limited
class CompactSpeedIndicator extends StatelessWidget {
  final double? speedKmh;

  const CompactSpeedIndicator({super.key, this.speedKmh});

  @override
  Widget build(BuildContext context) {
    final speed = speedKmh ?? 0;
    final color = _getSpeedColor(speed);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.speed, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            speedKmh != null ? speedKmh!.toStringAsFixed(0) : '--',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 2),
          const Text(
            'km/h',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Color _getSpeedColor(double speed) {
    if (speed < 1) return Colors.grey[600]!;
    if (speed < 20) return const Color(0xFF4CAF50);
    if (speed < 50) return const Color(0xFF2196F3);
    if (speed < 80) return const Color(0xFFFF9800);
    if (speed < 100) return const Color(0xFFFF5722);
    return const Color(0xFFF44336);
  }
}
