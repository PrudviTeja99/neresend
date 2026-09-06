import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/size_formatter.dart';
import '../../data/services/transfer_orchestrator.dart';
import '../state/orchestrator_provider.dart';

/// Bottom sheet dialog prompting the user to accept or decline an incoming transfer
class IncomingTransferModal extends StatefulWidget {
  final IncomingTransferPrompt prompt;

  const IncomingTransferModal({super.key, required this.prompt});

  static void show(BuildContext context, IncomingTransferPrompt prompt) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => IncomingTransferModal(prompt: prompt),
    );
  }

  @override
  State<IncomingTransferModal> createState() => _IncomingTransferModalState();
}

class _IncomingTransferModalState extends State<IncomingTransferModal> {
  bool _rememberDevice = false;

  @override
  Widget build(BuildContext context) {
    final sizeStr = SizeFormatter.formatBytes(widget.prompt.totalBytes);

    return Consumer(
      builder: (context, ref, _) {
        final orchestrator =
            ref.watch(transferOrchestratorProvider).asData?.value;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.file_download,
                        color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Incoming Transfer Request',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'From ${widget.prompt.senderAlias}',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Transfer Metadata Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Files to receive:',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 13)),
                        Text(
                          '${widget.prompt.totalFiles} ($sizeStr)',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    const Divider(height: 18, color: Colors.white12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Device Fingerprint:',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 13)),
                        Expanded(
                          child: Text(
                            widget.prompt.senderFingerprint,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: AppColors.accent,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (widget.prompt.isRemote &&
                        widget.prompt.sasEmojis.isNotEmpty) ...[
                      const Divider(height: 18, color: Colors.white12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('SAS Verification:',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 13)),
                          Text(
                            widget.prompt.sasEmojis,
                            style:
                                const TextStyle(fontSize: 18, letterSpacing: 4),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Remember Device Checkbox
              CheckboxListTile(
                value: _rememberDevice,
                onChanged: (val) =>
                    setState(() => _rememberDevice = val ?? false),
                title: const Text(
                  'Always accept transfers from this device',
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: AppColors.primary,
              ),
              const SizedBox(height: 16),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        if (orchestrator != null) {
                          await orchestrator.declineTransfer(
                              widget.prompt.request.transferId);
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.readyGreen,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        if (orchestrator != null) {
                          await orchestrator.acceptTransfer(
                            widget.prompt.request.transferId,
                            rememberDevice: _rememberDevice,
                            senderFingerprint: widget.prompt.senderFingerprint,
                          );
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Accept & Save',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
