import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Spotify-style docked bottom mini-player bar for background transfer tracking
class DockedTransferBar extends StatelessWidget {
  final String? activeFileName;
  final double progress; // 0.0 to 1.0
  final String speedText; // e.g. "48.2 MB/s"
  final String etaText;   // e.g. "ETA: 12s"
  final bool isPaused;
  final VoidCallback? onPauseToggle;
  final VoidCallback? onCancel;
  final VoidCallback? onTap;

  const DockedTransferBar({
    super.key,
    this.activeFileName,
    this.progress = 0.0,
    this.speedText = '',
    this.etaText = '',
    this.isPaused = false,
    this.onPauseToggle,
    this.onCancel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (activeFileName == null) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceHighlight),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Circular Progress Indicator
            SizedBox(
              width: 38,
              height: 38,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3.5,
                    backgroundColor: AppColors.surfaceHighlight,
                    color: AppColors.accent,
                  ),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // File Name & Metrics
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    activeFileName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        speedText,
                        style: const TextStyle(
                          color: AppColors.speedCyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (etaText.isNotEmpty) ...[
                        const Text(
                          ' • ',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                        Text(
                          etaText,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Quick Control Actions
            IconButton(
              icon: Icon(
                isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: AppColors.textPrimary,
              ),
              onPressed: onPauseToggle,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.offlineRed),
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

