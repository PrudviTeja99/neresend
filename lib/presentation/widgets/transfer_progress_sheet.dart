import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/size_formatter.dart';
import '../../core/utils/speed_calculator.dart';
import '../../domain/models/transfer_progress.dart';
import '../state/active_transfer_provider.dart';

/// Modal bottom sheet showing detailed multi-file transfer metrics, chunk status, and control actions
class TransferProgressSheet extends ConsumerWidget {
  const TransferProgressSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) => const TransferProgressSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(activeTransferProvider);

    if (progress == null) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No active transfer in progress',
              style: TextStyle(color: AppColors.textMuted, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    final percent = (progress.progressFraction * 100).toStringAsFixed(1);
    final speedStr = SpeedCalculator.formatSpeed(progress.speedBytesPerSecond);
    final etaStr = SpeedCalculator.formatEta(progress.estimatedTimeRemaining);
    final transferredStr = SizeFormatter.formatBytes(progress.bytesTransferred);
    final totalStr = SizeFormatter.formatBytes(progress.totalBytes);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceHighlight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress.currentFileName.isEmpty
                          ? 'Transferring files...'
                          : progress.currentFileName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'File ${progress.currentFileIndex + 1} of ${progress.totalFiles} • $percent%',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  speedStr,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.progressFraction,
              minHeight: 10,
              backgroundColor: AppColors.surfaceHighlight,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress.status == TransferStatus.paused
                    ? AppColors.scanningYellow
                    : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Stats Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$transferredStr / $totalStr',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              Text(
                etaStr,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Controls
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (progress.status == TransferStatus.paused) {
                      await ref.read(activeTransferProvider.notifier).resume();
                    } else {
                      await ref.read(activeTransferProvider.notifier).pause();
                    }
                  },
                  icon: Icon(
                    progress.status == TransferStatus.paused
                        ? Icons.play_arrow
                        : Icons.pause,
                    size: 18,
                  ),
                  label: Text(progress.status == TransferStatus.paused
                      ? 'Resume'
                      : 'Pause'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.offlineRed,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    await ref.read(activeTransferProvider.notifier).cancel();
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancel'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
