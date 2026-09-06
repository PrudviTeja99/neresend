import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/models/discovered_peer.dart';
import '../../domain/models/transfer_mode.dart';

/// Floating peer bubble node in the Nearby radar view
class PeerBubbleNode extends StatelessWidget {
  final DiscoveredPeer peer;
  final VoidCallback onTap;

  const PeerBubbleNode({
    super.key,
    required this.peer,
    required this.onTap,
  });

  IconData _getDeviceIcon(DeviceType type) {
    switch (type) {
      case DeviceType.android:
        return Icons.phone_android;
      case DeviceType.linux:
        return Icons.terminal;
      case DeviceType.windows:
        return Icons.laptop_windows;
      case DeviceType.macos:
      case DeviceType.ios:
        return Icons.apple;
      case DeviceType.web:
        return Icons.language;
      case DeviceType.unknown:
        return Icons.devices_other;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: peer.isTrusted ? AppColors.readyGreen : AppColors.primary,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (peer.isTrusted ? AppColors.readyGreen : AppColors.primary)
                  .withValues(alpha: 0.25),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.surfaceHighlight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getDeviceIcon(peer.deviceType),
                size: 18,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  peer.alias,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  peer.supportedMode == TransferMode.direct
                      ? 'Direct Link'
                      : 'Local Wi-Fi',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
