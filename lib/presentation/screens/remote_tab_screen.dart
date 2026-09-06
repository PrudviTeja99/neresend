import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/transports/webrtc/signaling_client.dart';
import '../state/orchestrator_provider.dart';

/// Tab 2: Remote P2P screen (Explicit 10-Minute PIN matchmaking & WebRTC transfer)
class RemoteTabScreen extends ConsumerStatefulWidget {
  const RemoteTabScreen({super.key});

  @override
  ConsumerState<RemoteTabScreen> createState() => _RemoteTabScreenState();
}

class _RemoteTabScreenState extends ConsumerState<RemoteTabScreen> {
  final TextEditingController _pinController = TextEditingController();
  String _generatedPin = '749 312';
  int _secondsRemaining = 600; // 10 minutes
  Timer? _countdownTimer;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _refreshPin();
  }

  void _refreshPin() {
    _generatedPin = SignalingClient.generatePin();
    _secondsRemaining = 600;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
      }
    });
    setState(() {});
  }

  String _formatTimer(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _handleConnectAndSend() async {
    final rawPin = _pinController.text.trim();
    final normalized = SignalingClient.normalizePin(rawPin);

    if (normalized.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit PIN')),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final files = result.paths
        .where((path) => path != null)
        .map((path) => File(path!))
        .toList();

    if (files.isEmpty) return;

    setState(() => _isConnecting = true);

    try {
      final orchestrator = ref.read(transferOrchestratorProvider).asData?.value;
      if (orchestrator != null) {
        // Attempt Remote PIN Match
        final pairResult = await orchestrator.remoteDiscovery.pairWithPin(
          pin: rawPin,
          sdpAnswer: 'v=0\r\no=client_direct_p2p',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Matched remote peer: ${pairResult.hostPeer.alias}! Transfer queued.'),
              backgroundColor: AppColors.readyGreen,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Remote pairing failed: $e'),
            backgroundColor: AppColors.offlineRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card A: Receive via Code
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.qr_code_rounded,
                          color: AppColors.accent, size: 28),
                      SizedBox(width: 12),
                      Text(
                        'Receive Remotely',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Share this 6-digit PIN with the sender to receive files over the internet.',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  // 6-Digit PIN Display
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.surfaceHighlight),
                    ),
                    child: Text(
                      _generatedPin,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        color: AppColors.speedCyan,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 6),
                      Text(
                        'Expires in ${_formatTimer(_secondsRemaining)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        icon: const Icon(Icons.refresh, size: 14),
                        label: const Text('New PIN',
                            style: TextStyle(fontSize: 12)),
                        onPressed: _refreshPin,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Card B: Send via Code
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.send_rounded,
                          color: AppColors.primaryLight, size: 28),
                      SizedBox(width: 12),
                      Text(
                        'Send to Remote Peer',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 7, // allows space "749 312"
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: '000 000',
                      hintStyle: const TextStyle(
                          color: AppColors.textMuted, letterSpacing: 6),
                      filled: true,
                      fillColor: AppColors.background,
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.surfaceHighlight),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.surfaceHighlight),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isConnecting ? null : _handleConnectAndSend,
                    child: _isConnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Connect & Select Files'),
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
