import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/discovered_peer.dart';
import '../state/identity_provider.dart';
import '../state/orchestrator_provider.dart';
import '../state/peer_list_provider.dart';
import '../state/readiness_state_provider.dart';
import '../widgets/animated_radar_canvas.dart';
import '../widgets/center_device_avatar.dart';
import '../widgets/peer_bubble_node.dart';

/// Tab 1: Nearby Radar screen with dynamic peer bubbles, zero-click readiness, and file picker
class NearbyTabScreen extends ConsumerWidget {
  const NearbyTabScreen({super.key});

  Future<void> _pickAndSendFiles(
    BuildContext context,
    WidgetRef ref,
    DiscoveredPeer peer,
  ) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final files = result.paths
        .where((path) => path != null)
        .map((path) => File(path!))
        .toList();

    if (files.isEmpty) return;

    final orchestrator = ref.read(transferOrchestratorProvider).asData?.value;
    if (orchestrator != null) {
      try {
        await orchestrator.sendFiles(peer, files);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Transfer failed: $e'),
                backgroundColor: AppColors.offlineRed),
          );
        }
      }
    }
  }

  DeviceReadinessState _mapReadiness(ReadinessState state) {
    switch (state) {
      case ReadinessState.ready:
        return DeviceReadinessState.ready;
      case ReadinessState.scanning:
        return DeviceReadinessState.scanning;
      case ReadinessState.offline:
        return DeviceReadinessState.offline;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityStateProvider);
    final peersAsync = ref.watch(peerListProvider);
    final readiness = ref.watch(readinessStateProvider);

    return AnimatedRadarCanvas(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final center =
              Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
          final radius =
              math.min(constraints.maxWidth, constraints.maxHeight) * 0.35;

          final peers = peersAsync.asData?.value ?? [];

          return Stack(
            alignment: Alignment.center,
            children: [
              // Floating Peer Bubbles positioned radially
              ...List.generate(peers.length, (index) {
                final peer = peers[index];
                final angle =
                    (2 * math.pi / math.max(peers.length, 1)) * index -
                        (math.pi / 2);
                final dx = center.dx + radius * math.cos(angle) - 70;
                final dy = center.dy + radius * math.sin(angle) - 25;

                return Positioned(
                  left: dx.clamp(16.0, constraints.maxWidth - 160.0),
                  top: dy.clamp(16.0, constraints.maxHeight - 120.0),
                  child: PeerBubbleNode(
                    peer: peer,
                    onTap: () => _pickAndSendFiles(context, ref, peer),
                  ),
                );
              }),

              // Central Device Avatar
              identityAsync.when(
                data: (identity) => CenterDeviceAvatar(
                  alias: identity.alias,
                  readinessState: _mapReadiness(readiness),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Identity Fingerprint: ${identity.fingerprint}'),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  },
                ),
                loading: () =>
                    const CircularProgressIndicator(color: AppColors.accent),
                error: (err, _) => Text(
                  'Error: $err',
                  style: const TextStyle(color: AppColors.offlineRed),
                ),
              ),

              // Bottom Action Button
              Positioned(
                bottom: 24,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 22),
                  label: Text(peers.isEmpty
                      ? 'Select Peer to Send'
                      : 'Send Files (${peers.length} Nearby)'),
                  onPressed: peers.isNotEmpty
                      ? () => _pickAndSendFiles(context, ref, peers.first)
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Searching for nearby DropFlow devices on local Wi-Fi / BLE...'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
