import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../state/identity_provider.dart';

/// Modal dialog for device alias modification and cryptographic identity verification
class SettingsModal extends ConsumerStatefulWidget {
  const SettingsModal({super.key});

  @override
  ConsumerState<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends ConsumerState<SettingsModal> {
  late final TextEditingController _aliasController;

  @override
  void initState() {
    super.initState();
    final identity = ref.read(identityStateProvider).valueOrNull;
    _aliasController = TextEditingController(text: identity?.alias ?? '');
  }

  @override
  void dispose() {
    _aliasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(identityStateProvider).valueOrNull;

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
                'Settings & Identity',
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
          const SizedBox(height: 20),

          // Device Alias
          TextField(
            controller: _aliasController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Device Name (Visible to peers)',
              labelStyle: const TextStyle(color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.surfaceHighlight),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check_rounded, color: AppColors.accent),
                onPressed: () {
                  ref.read(identityStateProvider.notifier).updateAlias(_aliasController.text);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Device name updated!')),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Permanent Cryptographic Identity Card
          if (identity != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceHighlight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 18, color: AppColors.trustedBadge),
                      SizedBox(width: 8),
                      Text(
                        'Ed25519 Identity Fingerprint',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    identity.fingerprint,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

