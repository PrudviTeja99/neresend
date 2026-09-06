import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/size_formatter.dart';
import '../state/orchestrator_provider.dart';

/// Transfer history modal displaying past sent and received files
class HistoryModal extends StatelessWidget {
  const HistoryModal({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const HistoryModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, y • HH:mm');

    return Consumer(
      builder: (context, ref, _) {
        final storage = ref.watch(storageServiceProvider);
        final history = storage.history;

        return Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.surfaceHighlight),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.history_rounded,
                            color: AppColors.primary, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Transfer History',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textMuted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // History List
                Expanded(
                  child: history.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_open_rounded,
                                  size: 48,
                                  color: AppColors.textMuted
                                      .withValues(alpha: 0.4)),
                              const SizedBox(height: 12),
                              const Text(
                                'No transfers recorded yet',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: history.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final entry = history[index];
                            final sizeStr =
                                SizeFormatter.formatBytes(entry.totalBytes);
                            final timeStr = dateFormat.format(entry.timestamp);

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceHighlight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: entry.isSender
                                          ? AppColors.primary
                                              .withValues(alpha: 0.15)
                                          : AppColors.readyGreen
                                              .withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      entry.isSender
                                          ? Icons.arrow_upward_rounded
                                          : Icons.arrow_downward_rounded,
                                      color: entry.isSender
                                          ? AppColors.primary
                                          : AppColors.readyGreen,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.fileName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: AppColors.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${entry.isSender ? 'To' : 'From'} ${entry.peerAlias} • $sizeStr',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textMuted),
                                        ),
                                        Text(
                                          timeStr,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.textMuted
                                                .withValues(alpha: 0.7),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
