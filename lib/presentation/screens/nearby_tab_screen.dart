import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../state/identity_provider.dart';
import '../widgets/center_device_avatar.dart';

/// Tab 1: Nearby Radar screen (Local LAN & Direct Link proximity sharing)
class NearbyTabScreen extends ConsumerWidget {
  final VoidCallback? onSendFiles;

  const NearbyTabScreen({super.key, this.onSendFiles});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityStateProvider);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Concentric Radar Background Rings
        CustomPaint(
          size: Size.infinite,
          painter: _RadarBackgroundPainter(),
        ),

        // Center Device Avatar (Zero-Click Receiver Readiness)
        identityAsync.when(
          data: (identity) => CenterDeviceAvatar(
            alias: identity.alias,
            readinessState: DeviceReadinessState.ready,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Identity Fingerprint: ${identity.fingerprint}'),
                  duration: const Duration(seconds: 3),
                ),
              );
            },
          ),
          loading: () => const CircularProgressIndicator(color: AppColors.accent),
          error: (err, _) => Text(
            'Error: $err',
            style: const TextStyle(color: AppColors.offlineRed),
          ),
        ),

        // Floating Action Button to Send Files
        Positioned(
          bottom: 24,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.add_rounded, size: 22),
            label: const Text('Send Files'),
            onPressed: onSendFiles ?? () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RadarBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.45;

    final paint = Paint()
      ..color = AppColors.surfaceHighlight.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, (maxRadius / 3) * i, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

