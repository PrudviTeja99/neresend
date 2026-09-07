import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/transports/webrtc/remote_signaling_client.dart';
import '../state/orchestrator_provider.dart';
import '../widgets/qr_code_card.dart';

/// Tab 2: Remote P2P screen (Explicit 5-Minute PIN/QR matchmaking & WebRTC transfer)
class RemoteTabScreen extends ConsumerStatefulWidget {
  const RemoteTabScreen({super.key});

  @override
  ConsumerState<RemoteTabScreen> createState() => _RemoteTabScreenState();
}

class _RemoteTabScreenState extends ConsumerState<RemoteTabScreen> {
  final TextEditingController _pinController = TextEditingController();
  RemoteSessionInfo? _sessionInfo;
  String _generatedPin = '550 573';
  int _secondsRemaining = 300; // 5 minutes
  Timer? _countdownTimer;
  bool _isCreatingSession = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initOrRefreshSession();
    });
  }

  Future<void> _initOrRefreshSession() async {
    final orchestrator = ref.read(transferOrchestratorProvider).asData?.value;
    if (orchestrator == null) return;

    setState(() => _isCreatingSession = true);
    _countdownTimer?.cancel();

    try {
      final info = await orchestrator.startRemoteHostSession();
      if (mounted) {
        setState(() {
          _sessionInfo = info;
          _generatedPin = info.pin;
          _secondsRemaining = info.secondsRemaining;
          _isCreatingSession = false;
        });

        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_secondsRemaining > 0) {
            setState(() => _secondsRemaining--);
          } else {
            timer.cancel();
            if (mounted) setState(() {});
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isCreatingSession = false);
      }
    }
  }

  String _formatTimer(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _handleConnectAndSend() async {
    final rawInput = _pinController.text.trim();
    final parsed = RemoteSessionInfo.parseInviteUri(rawInput);
    final normalized = RemoteSignalingClient.normalizePin(parsed.pin);

    if (parsed.sessionId == null && normalized.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit PIN')),
      );
      return;
    }

    final result = await FilePicker.pickFiles();
    if (result.isEmpty) return;

    final files = result
        .where((file) => file.path != null)
        .map((file) => File(file.path!))
        .toList();

    if (files.isEmpty) return;

    setState(() => _isConnecting = true);

    try {
      final orchestrator = ref.read(transferOrchestratorProvider).asData?.value;
      if (orchestrator != null) {
        await orchestrator.sendRemoteFiles(
          pinOrUri: rawInput,
          files: files,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connected to remote peer! Transfer started.'),
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
    final inviteUri = _sessionInfo?.inviteUri ??
        'neresend://pair?session=init&pin=${_generatedPin.replaceAll(' ', '')}';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card A: Receive Remotely (QR + PIN)
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
                      const SizedBox(height: 12),
                      const Text(
                        'Share this 6-digit PIN or scan the QR code to receive files directly over the internet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 18),

                      // QR Code Card
                      if (_isCreatingSession)
                        const SizedBox(
                          height: 140,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        QrCodeCard(
                          data: inviteUri,
                          size: 140,
                        ),

                      const SizedBox(height: 16),

                      // 6-Digit PIN Display
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
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
                            _secondsRemaining > 0
                                ? 'Expires in ${_formatTimer(_secondsRemaining)}'
                                : 'PIN Expired',
                            style: TextStyle(
                              fontSize: 12,
                              color: _secondsRemaining > 0
                                  ? AppColors.textMuted
                                  : AppColors.offlineRed,
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton.icon(
                            icon: const Icon(Icons.refresh, size: 14),
                            label: const Text('New PIN',
                                style: TextStyle(fontSize: 12)),
                            onPressed:
                                _isCreatingSession ? null : _initOrRefreshSession,
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            tooltip: 'Copy Invite Link',
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: _generatedPin));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('PIN copied to clipboard!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Card B: Send to Remote Peer
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
                        keyboardType: TextInputType.text,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                          color: AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: '550 573 or neresend://...',
                          hintStyle: const TextStyle(
                              color: AppColors.textMuted,
                              letterSpacing: 2,
                              fontSize: 14),
                          filled: true,
                          fillColor: AppColors.background,
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppColors.surfaceHighlight),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppColors.surfaceHighlight),
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
        ),
      ),
    );
  }
}
