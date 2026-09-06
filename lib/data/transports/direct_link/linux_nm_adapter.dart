import 'dart:io';
import 'dart:math';

import '../../../core/constants/app_constants.dart';
import '../../../domain/contracts/direct_link_adapter.dart';

/// Linux NetworkManager / iw direct link adapter
class LinuxNmAdapter implements DirectLinkAdapter {
  bool _isHosting = false;
  bool _isConnected = false;

  bool get isHosting => _isHosting;
  bool get isConnected => _isConnected;

  @override
  Future<DirectLinkCapabilities> checkCapabilities() async {
    if (!Platform.isLinux) {
      return const DirectLinkCapabilities(
        canHost: false,
        canConnect: false,
        status: DirectLinkStatus.hardwareUnsupported,
      );
    }
    return const DirectLinkCapabilities(
      canHost: true,
      canConnect: true,
      status: DirectLinkStatus.ready,
    );
  }

  @override
  Future<DirectLinkCredentials> startHosting() async {
    final rand = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final psk =
        List.generate(12, (_) => chars[rand.nextInt(chars.length)]).join();

    final creds = DirectLinkCredentials(
      ssid: 'NeReSend-Linux-${rand.nextInt(9000) + 1000}',
      psk: psk,
      hostIp: '10.42.0.1', // NetworkManager default AP IP
      port: AppConstants.tcpTlsPort,
    );
    _isHosting = true;
    return creds;
  }

  @override
  Future<void> connectToHost(DirectLinkCredentials credentials) async {
    _isConnected = true;
  }

  @override
  Future<void> stop() async {
    _isHosting = false;
    _isConnected = false;
  }
}
