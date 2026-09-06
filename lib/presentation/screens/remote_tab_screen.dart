import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Tab 2: Remote P2P screen (Explicit 10-Minute PIN & QR Code internet pairing)
class RemoteTabScreen extends StatefulWidget {
  const RemoteTabScreen({super.key});

  @override
  State<RemoteTabScreen> createState() => _RemoteTabScreenState();
}

class _RemoteTabScreenState extends State<RemoteTabScreen> {
  final TextEditingController _pinController = TextEditingController();

  @override
  void dispose() {
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
                      Icon(Icons.qr_code_rounded, color: AppColors.accent, size: 28),
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
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  // 6-Digit PIN Display
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.surfaceHighlight),
                    ),
                    child: const Text(
                      '749 312',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        color: AppColors.speedCyan,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timer_outlined, size: 14, color: AppColors.textMuted),
                      SizedBox(width: 6),
                      Text(
                        'Expires in 09:42',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
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
                      Icon(Icons.send_rounded, color: AppColors.primaryLight, size: 28),
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
                    maxLength: 6,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 6,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: '000000',
                      hintStyle: const TextStyle(color: AppColors.textMuted, letterSpacing: 6),
                      filled: true,
                      fillColor: AppColors.background,
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.surfaceHighlight),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.surfaceHighlight),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {},
                    child: const Text('Connect & Select Files'),
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

