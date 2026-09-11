// widgets/pulsing_location_marker.dart
// inDrive/ride-hailing style pulsating radar marker: concentric circles
// expand outward from the user's live location and fade out on loop,
// giving a "searching / live tracking" feel on the map.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PulsingLocationMarker extends StatefulWidget {
  final double size;
  final Color color;
  final int ringCount;
  final Duration duration;

  const PulsingLocationMarker({
    super.key,
    this.size = 120,
    this.color = AppColors.lime,
    this.ringCount = 3,
    this.duration = const Duration(milliseconds: 2400),
  });

  @override
  State<PulsingLocationMarker> createState() => _PulsingLocationMarkerState();
}

class _PulsingLocationMarkerState extends State<PulsingLocationMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _RipplePainter(
                progress: _controller.value,
                color: widget.color,
                ringCount: widget.ringCount,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double progress;
  final Color color;
  final int ringCount;

  _RipplePainter({
    required this.progress,
    required this.color,
    required this.ringCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;

    // Concentric waves: each ring is offset in phase so a new one is born
    // roughly every `duration / ringCount`, expanding & fading like radar.
    for (var i = 0; i < ringCount; i++) {
      final phase = (progress + i / ringCount) % 1.0;
      final radius = maxRadius * Curves.easeOut.transform(phase);
      final opacity = (1 - phase).clamp(0.0, 1.0) * 0.45;
      if (radius <= 0 || opacity <= 0) continue;
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius, paint);
    }

    // Soft static halo behind the dot so the pulse always has a base glow.
    canvas.drawCircle(
      center,
      maxRadius * 0.22,
      Paint()..color = color.withValues(alpha: 0.18),
    );

    // Center dot (current exact position) with a white ring, like the
    // live-location puck seen in InDrive/Uber style maps.
    canvas.drawCircle(center, 10, Paint()..color = Colors.white);
    canvas.drawCircle(center, 8, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.ringCount != ringCount;
}
