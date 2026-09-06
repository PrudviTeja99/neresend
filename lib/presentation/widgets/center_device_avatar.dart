import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

enum DeviceReadinessState {
  ready,
  scanning,
  offline;

  Color get color {
    switch (this) {
      case DeviceReadinessState.ready:
        return AppColors.readyGreen;
      case DeviceReadinessState.scanning:
        return AppColors.scanningYellow;
      case DeviceReadinessState.offline:
        return AppColors.offlineRed;
    }
  }

  Color get glowColor {
    switch (this) {
      case DeviceReadinessState.ready:
        return AppColors.readyGreenGlow;
      case DeviceReadinessState.scanning:
        return AppColors.scanningYellowGlow;
      case DeviceReadinessState.offline:
        return AppColors.offlineRedGlow;
    }
  }

  String get label {
    switch (this) {
      case DeviceReadinessState.ready:
        return 'Ready to receive';
      case DeviceReadinessState.scanning:
        return 'Searching nearby...';
      case DeviceReadinessState.offline:
        return 'Wi-Fi Disabled';
    }
  }

  String get emoji {
    switch (this) {
      case DeviceReadinessState.ready:
        return '🟢';
      case DeviceReadinessState.scanning:
        return '🟡';
      case DeviceReadinessState.offline:
        return '🔴';
    }
  }
}

/// Breathing glow avatar node positioned at the center of the Nearby radar
class CenterDeviceAvatar extends StatefulWidget {
  final String alias;
  final DeviceReadinessState readinessState;
  final VoidCallback? onTap;

  const CenterDeviceAvatar({
    super.key,
    required this.alias,
    this.readinessState = DeviceReadinessState.ready,
    this.onTap,
  });

  @override
  State<CenterDeviceAvatar> createState() => _CenterDeviceAvatarState();
}

class _CenterDeviceAvatarState extends State<CenterDeviceAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surface,
                    border: Border.all(
                      color: widget.readinessState.color,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.readinessState.glowColor,
                        blurRadius: 24,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.devices_rounded,
                      color: widget.readinessState.color,
                      size: 38,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            widget.alias,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceHighlight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.readinessState.emoji,
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.readinessState.label,
                  style: TextStyle(
                    color: widget.readinessState.color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

