import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Animated radar background canvas with concentric pulse rings and rotating scan beam
class AnimatedRadarCanvas extends StatefulWidget {
  final Widget child;

  const AnimatedRadarCanvas({super.key, required this.child});

  @override
  State<AnimatedRadarCanvas> createState() => _AnimatedRadarCanvasState();
}

class _AnimatedRadarCanvasState extends State<AnimatedRadarCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _RadarPainter(animationProgress: _controller.value),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double animationProgress;

  _RadarPainter({required this.animationProgress});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) * 0.45;

    final ringPaint = Paint()
      ..color = AppColors.surfaceHighlight.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 1. Static Reference Rings
    for (int i = 1; i <= 3; i++) {
      final r = (maxRadius / 3) * i;
      canvas.drawCircle(center, r, ringPaint);
    }

    // 2. Expanding Concentric Pulse Waves
    for (int i = 0; i < 2; i++) {
      final waveProgress = (animationProgress + (i * 0.5)) % 1.0;
      final currentRadius = waveProgress * maxRadius;
      final opacity = (1.0 - waveProgress).clamp(0.0, 0.6);

      final pulsePaint = Paint()
        ..color = AppColors.primary.withValues(alpha: opacity * 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawCircle(center, currentRadius, pulsePaint);
    }

    // 3. Rotating Scan Sweep Beam
    final angle = animationProgress * 2 * math.pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: FractionalOffset.center,
        startAngle: 0.0,
        endAngle: math.pi / 2,
        colors: [
          AppColors.primary.withValues(alpha: 0.15),
          AppColors.primary.withValues(alpha: 0.0),
        ],
        transform: GradientRotation(angle),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxRadius, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.animationProgress != animationProgress;
}
