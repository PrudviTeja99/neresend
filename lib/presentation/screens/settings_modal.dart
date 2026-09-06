import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../state/identity_provider.dart';
import '../state/orchestrator_provider.dart';
import '../state/trusted_device_provider.dart';

/// Settings modal dialog for configuring device alias, viewing cryptographic keys, and trusted devices
class SettingsModal extends StatefulWidget {
  const SettingsModal({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const SettingsModal(),
    );
  }

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  late final TextEditingController _aliasController;
  bool _isEditingAlias = false;

  @override
  void initState() {
    super.initState();
    _aliasController = TextEditingController();
  }

  @override
  void dispose() {
    _aliasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final identityAsync = ref.watch(identityStateProvider);
        final trustedDevices = ref.watch(trustedDeviceProvider);
        final storage = ref.watch(storageServiceProvider);

        return Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.surfaceHighlight),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.settings,
                              color: AppColors.primary, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon:
                            const Icon(Icons.close, color: AppColors.textMuted),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Device Identity Section
                  const Text(
                    'DEVICE IDENTITY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  identityAsync.when(
                    data: (identity) {
                      if (!_isEditingAlias && _aliasController.text.isEmpty) {
                        _aliasController.text = identity.alias;
                      }

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHighlight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _isEditingAlias
                                      ? TextField(
                                          controller: _aliasController,
                                          style: const TextStyle(
                                              color: AppColors.textPrimary),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            border: UnderlineInputBorder(),
                                            hintText: 'Enter device name',
                                          ),
                                        )
                                      : Text(
                                          identity.alias,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    _isEditingAlias ? Icons.check : Icons.edit,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                  onPressed: () async {
                                    if (_isEditingAlias) {
                                      final newAlias =
                                          _aliasController.text.trim();
                                      if (newAlias.isNotEmpty) {
                                        await ref
                                            .read(
                                                identityStateProvider.notifier)
                                            .updateAlias(newAlias);
                                      }
                                    }
                                    setState(() =>
                                        _isEditingAlias = !_isEditingAlias);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Ed25519 Fingerprint:',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              identity.fingerprint,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Text('Error: $err',
                        style: const TextStyle(color: AppColors.offlineRed)),
                  ),
                  const SizedBox(height: 20),

                  // Trusted Devices Section
                  const Text(
                    'TRUSTED DEVICES (AUTO-ACCEPT)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (trustedDevices.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHighlight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'No trusted devices pinned yet.\nCheck "Always accept" on incoming transfers.',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    )
                  else
                    ...trustedDevices.map((fp) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHighlight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.verified_user,
                                  color: AppColors.readyGreen, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  fp,
                                  style: const TextStyle(
                                      fontFamily: 'monospace', fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    size: 16, color: AppColors.offlineRed),
                                onPressed: () => ref
                                    .read(trustedDeviceProvider.notifier)
                                    .unpinDevice(fp),
                              ),
                            ],
                          ),
                        )),
                  const SizedBox(height: 20),

                  // Download Directory
                  const Text(
                    'STORAGE & DOWNLOADS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder(
                    future: storage.getDefaultDownloadDirectory(),
                    builder: (context, snapshot) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHighlight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          snapshot.data?.path ?? 'Resolving download folder...',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textPrimary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // Version / Info
                  Center(
                    child: Text(
                      'DropFlow v1.0.0 • Pure P2P Zero-Cloud Protocol',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted.withValues(alpha: 0.6)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
