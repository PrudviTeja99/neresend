import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Modal dialog showing completed and interrupted transfer history
class HistoryModal extends StatelessWidget {
  const HistoryModal({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Transfer History',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.history_toggle_off_rounded, size: 48, color: AppColors.textMuted),
                  SizedBox(height: 12),
                  Text(
                    'No transfers yet',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

